// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Read-only approval boundary consumed by Unight accounts.
interface IUnightPolicyRegistry {
    /// @notice Whether a pool identity is approved.
    function isPoolApproved(bytes32 poolId) external view returns (bool);

    /// @notice Whether a Midnight market identity is approved.
    function isMarketApproved(bytes32 marketId) external view returns (bool);

    /// @notice Whether an offer ratifier is approved.
    function isRatifierApproved(address ratifier) external view returns (bool);

    /// @notice Whether a dormancy oracle is approved.
    function isDormancyOracleApproved(address oracle) external view returns (bool);
}
