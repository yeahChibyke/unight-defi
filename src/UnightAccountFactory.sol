// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IDormancyOracle} from "./interfaces/IDormancyOracle.sol";
import {IMidnight} from "./interfaces/IMidnight.sol";
import {IUnightPolicyRegistry} from "./interfaces/IUnightPolicyRegistry.sol";
import {UnightAccount} from "./UnightAccount.sol";

/// @notice CREATE2 factory for one immutable account per LP position.
contract UnightAccountFactory {
    IPositionManager public immutable positionManager;
    IPoolManager public immutable poolManager;
    IMidnight public immutable midnight;
    IUnightPolicyRegistry public immutable registry;

    mapping(address owner => mapping(uint256 positionId => address account)) public accountOf;

    error AccountExists();

    event AccountCreated(address indexed owner, uint256 indexed positionId, address indexed account);

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

    function createAccount(
        address owner_,
        uint256 positionId,
        address loanToken,
        bytes32 expectedPoolId,
        IDormancyOracle dormancyOracle,
        address bidRatifier
    ) external returns (address account) {
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
