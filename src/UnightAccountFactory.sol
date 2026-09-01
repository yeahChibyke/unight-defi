// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IDormancyOracle} from "./interfaces/IDormancyOracle.sol";
import {IMidnight} from "./interfaces/IMidnight.sol";
import {IUnightPolicyRegistry} from "./interfaces/IUnightPolicyRegistry.sol";
import {UnightAccount} from "./UnightAccount.sol";

/// @title Unight Account Factory
/// @notice CREATE2 factory that deploys one immutable account for each LP position.
/// @dev The factory shares canonical protocol addresses across accounts. Account
///      initialization still validates the selected pool and dormancy oracle.
contract UnightAccountFactory {
    /// @notice Canonical Uniswap v4 PositionManager shared by new accounts.
    IPositionManager public immutable positionManager;
    /// @notice Canonical Uniswap v4 PoolManager shared by new accounts.
    IPoolManager public immutable poolManager;
    /// @notice Canonical Midnight protocol shared by new accounts.
    IMidnight public immutable midnight;
    /// @notice Governance registry shared by new accounts.
    IUnightPolicyRegistry public immutable registry;

    /// @notice Account deployed for an LP and position, if one exists.
    mapping(address owner => mapping(uint256 positionId => address account)) public accountOf;

    error AccountExists();
    error NotPositionOwner();

    event AccountCreated(address indexed owner, uint256 indexed positionId, address indexed account);

    /// @param positionManager_ Canonical Uniswap v4 PositionManager.
    /// @param poolManager_ Canonical Uniswap v4 PoolManager.
    /// @param midnight_ Canonical Midnight lending protocol.
    /// @param registry_ Registry used by every created account.
    constructor(
        IPositionManager positionManager_,
        IPoolManager poolManager_,
        IMidnight midnight_,
        IUnightPolicyRegistry registry_
    ) {
        require(
            address(positionManager_) != address(0) && address(poolManager_) != address(0)
                && address(midnight_) != address(0) && address(registry_) != address(0),
            "UNIGHT_ZERO_ADDRESS"
        );
        positionManager = positionManager_;
        poolManager = poolManager_;
        midnight = midnight_;
        registry = registry_;
    }

    /// @notice Deploys a deterministic account for one LP position.
    /// @dev Only the current owner of the position NFT may submit the
    ///      deployment. The caller supplies the account owner, which is
    ///      typically themselves but need not be. Requiring NFT ownership at
    ///      creation time prevents a third party from registering another LP's
    ///      owner-position slot to grief their account.
    /// @param owner_ LP that will own the new account.
    /// @param positionId Uniswap v4 position NFT assigned to the account.
    /// @param loanToken Token used to fund Midnight settlements.
    /// @param expectedPoolId Pool identity accepted by the account.
    /// @param dormancyOracle Historical terminality oracle.
    /// @param bidRatifier Ratifier allowed to register maker-bid contexts.
    /// @return account Address of the newly deployed account.
    function createAccount(
        address owner_,
        uint256 positionId,
        address loanToken,
        bytes32 expectedPoolId,
        IDormancyOracle dormancyOracle,
        address bidRatifier
    ) external returns (address account) {
        if (IERC721(address(positionManager)).ownerOf(positionId) != msg.sender) {
            revert NotPositionOwner();
        }
        if (accountOf[owner_][positionId] != address(0)) revert AccountExists();
        bytes32 salt = keccak256(abi.encode(owner_, positionId, expectedPoolId, loanToken));
        account = address(
            new UnightAccount{salt: salt}(
                owner_,
                positionId,
                positionManager,
                poolManager,
                midnight,
                loanToken,
                expectedPoolId,
                dormancyOracle,
                registry,
                bidRatifier
            )
        );
        accountOf[owner_][positionId] = account;
        emit AccountCreated(owner_, positionId, account);
    }

    /// @notice Computes the CREATE2 address for a prospective account.
    /// @dev The result is valid only while the factory configuration and all
    ///      constructor arguments remain unchanged.
    /// @param owner_ LP that will own the prospective account.
    /// @param positionId Uniswap v4 position NFT assigned to the account.
    /// @param loanToken Token used to fund Midnight settlements.
    /// @param expectedPoolId Pool identity accepted by the account.
    /// @param dormancyOracle Historical terminality oracle.
    /// @param bidRatifier Ratifier allowed to register maker-bid contexts.
    /// @return predicted CREATE2 account address.
    function predictAccount(
        address owner_,
        uint256 positionId,
        address loanToken,
        bytes32 expectedPoolId,
        IDormancyOracle dormancyOracle,
        address bidRatifier
    ) external view returns (address predicted) {
        bytes32 salt = keccak256(abi.encode(owner_, positionId, expectedPoolId, loanToken));
        bytes memory initCode = abi.encodePacked(
            type(UnightAccount).creationCode,
            abi.encode(
                owner_,
                positionId,
                positionManager,
                poolManager,
                midnight,
                loanToken,
                expectedPoolId,
                dormancyOracle,
                registry,
                bidRatifier
            )
        );
        predicted = address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(initCode)))))
        );
    }
}
