// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IUnightPolicyRegistry} from "./interfaces/IUnightPolicyRegistry.sol";

/// @notice Governance-controlled allowlist. It does not hold funds and cannot
///         change an account's immutable protocol addresses or LP policy.
contract UnightPolicyRegistry is IUnightPolicyRegistry {
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

    constructor(address owner_) {
        require(owner_ != address(0), "UNIGHT_ZERO_OWNER");
        owner = owner_;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function setPoolApproval(bytes32 poolId, bool approved) external onlyOwner {
        _pools[poolId] = approved;
        emit PoolApprovalSet(poolId, approved);
    }

    function setMarketApproval(bytes32 marketId, bool approved) external onlyOwner {
        _markets[marketId] = approved;
        emit MarketApprovalSet(marketId, approved);
    }

    function setRatifierApproval(address ratifier, bool approved) external onlyOwner {
        _ratifiers[ratifier] = approved;
        emit RatifierApprovalSet(ratifier, approved);
    }

    function setDormancyOracleApproval(address oracle, bool approved) external onlyOwner {
        _oracles[oracle] = approved;
        emit DormancyOracleApprovalSet(oracle, approved);
    }

    function isPoolApproved(bytes32 poolId) external view returns (bool) {
        return _pools[poolId];
    }

    function isMarketApproved(bytes32 marketId) external view returns (bool) {
        return _markets[marketId];
    }

    function isRatifierApproved(address ratifier) external view returns (bool) {
        return _ratifiers[ratifier];
    }

    function isDormancyOracleApproved(address oracle) external view returns (bool) {
        return _oracles[oracle];
    }
}
