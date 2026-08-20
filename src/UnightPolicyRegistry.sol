// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IUnightPolicyRegistry} from "./interfaces/IUnightPolicyRegistry.sol";

/// @title Unight Policy Registry
/// @notice Governance-controlled allowlist for pools, markets, ratifiers, and
///         dormancy oracles accepted by Unight accounts.
/// @dev The registry does not hold funds and cannot change an account's immutable
///      protocol addresses or an already-installed LP policy.
contract UnightPolicyRegistry is IUnightPolicyRegistry {
    /// @notice Governance address allowed to update approvals.
    address public immutable owner;

    mapping(bytes32 poolId => bool approved) private _pools;
    mapping(bytes32 marketId => bool approved) private _markets;
    mapping(address ratifier => bool approved) private _ratifiers;
    mapping(address oracle => bool approved) private _oracles;

    error NotOwner();

    event PoolApprovalSet(bytes32 indexed poolId, bool approved);
    event MarketApprovalSet(bytes32 indexed marketId, bool approved);
    event RatifierApprovalSet(address indexed ratifier, bool approved);
    event DormancyOracleApprovalSet(address indexed oracle, bool approved);

    /// @param owner_ Address allowed to manage protocol-component approvals.
    constructor(address owner_) {
        require(owner_ != address(0), "UNIGHT_ZERO_OWNER");
        owner = owner_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @notice Approves or revokes a Uniswap v4 pool identity.
    function setPoolApproval(bytes32 poolId, bool approved) external onlyOwner {
        _pools[poolId] = approved;
        emit PoolApprovalSet(poolId, approved);
    }

    /// @notice Approves or revokes a Midnight market identity.
    function setMarketApproval(bytes32 marketId, bool approved) external onlyOwner {
        _markets[marketId] = approved;
        emit MarketApprovalSet(marketId, approved);
    }

    /// @notice Approves or revokes an offer ratifier for auto-lend execution.
    function setRatifierApproval(address ratifier, bool approved) external onlyOwner {
        _ratifiers[ratifier] = approved;
        emit RatifierApprovalSet(ratifier, approved);
    }

    /// @notice Approves or revokes a historical dormancy oracle.
    function setDormancyOracleApproval(address oracle, bool approved) external onlyOwner {
        _oracles[oracle] = approved;
        emit DormancyOracleApprovalSet(oracle, approved);
    }

    /// @notice Returns whether a pool identity is approved.
    function isPoolApproved(bytes32 poolId) external view returns (bool) {
        return _pools[poolId];
    }

    /// @notice Returns whether a Midnight market identity is approved.
    function isMarketApproved(bytes32 marketId) external view returns (bool) {
        return _markets[marketId];
    }

    /// @notice Returns whether an offer ratifier is approved.
    function isRatifierApproved(address ratifier) external view returns (bool) {
        return _ratifiers[ratifier];
    }

    /// @notice Returns whether a dormancy oracle is approved.
    function isDormancyOracleApproved(address oracle) external view returns (bool) {
        return _oracles[oracle];
    }
}
