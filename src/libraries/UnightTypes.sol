// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Risk and execution limits applied by one Unight LP account.
struct UnightPolicy {
    /// @notice Midnight market to which new credit may be committed.
    bytes32 marketId;
    /// @notice Lifetime gross buyer-assets cap for the account.
    uint256 globalCap;
    /// @notice Gross buyer-assets cap for auto-lend executions.
    uint256 autoLendCap;
    /// @notice Gross buyer-assets cap for maker-bid executions.
    uint256 bidBoardCap;
    /// @notice Principal reserved for future position reactivation.
    uint256 reactivationReserve;
    /// @notice Minimum annualized net rate in WAD precision.
    uint256 minNetRateWad;
    /// @notice Maximum continuous fee accepted by the callback.
    uint256 maxContinuousFee;
    /// @notice Maximum settlement fee accepted by the callback.
    uint256 maxSettlementFee;
    /// @notice Latest timestamp at which the policy may execute.
    uint256 expiry;
    /// @notice Historical dwell required by the dormancy oracle.
    uint32 minimumDwell;
    /// @notice Tick distance required beyond the position boundary.
    uint24 tickBuffer;
    /// @notice Maximum fraction of terminal principal that may be lent, in BPS.
    uint16 maxLendableBps;
    /// @notice Whether this policy accepts new executions.
    bool enabled;
}
