// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

struct UnightPolicy {
    bytes32 marketId;
    uint256 globalCap;
    uint256 autoLendCap;
    uint256 bidBoardCap;
    uint256 reactivationReserve;
    uint256 minNetRateWad;
    uint256 maxContinuousFee;
    uint256 maxSettlementFee;
    uint256 expiry;
    uint32 minimumDwell;
    uint24 tickBuffer;
    uint16 maxLendableBps;
    bool enabled;
}
