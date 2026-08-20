// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal, pinned Unight boundary for the Midnight lending protocol.
/// @dev Keep this file synchronized with the deployed Midnight interface before
///      production deployment. It is deliberately local because this repository
///      does not vendor Midnight's Solidity package yet.
interface IMidnight {
    struct CollateralParams {
        address token;
        uint256 lltv;
        uint256 liquidationCursor;
        address oracle;
    }

    struct Market {
        uint256 chainId;
        address midnight;
        address loanToken;
        CollateralParams[] collateralParams;
        uint256 maturity;
        uint256 rcfThreshold;
        address enterGate;
        address liquidatorGate;
    }

    struct Offer {
        Market market;
        bool buy;
        address maker;
        uint256 start;
        uint256 expiry;
        uint256 tick;
        bytes32 group;
        address callback;
        bytes callbackData;
        address receiverIfMakerIsSeller;
        address ratifier;
        bool reduceOnly;
        uint128 maxUnits;
        uint128 maxAssets;
        uint256 continuousFeeCap;
    }

    struct MarketState {
        uint128 totalCredit;
        uint128 totalDebt;
        uint128 totalCollateral;
        uint128 lastLossFactor;
        uint128 lastAccrual;
        uint128 treasury;
        uint128 rateAtMaturity;
        uint128 rateStart;
        uint128 rateEnd;
    }

    function take(
        Offer memory offer,
        bytes memory ratifierData,
        uint256 units,
        address taker,
        address receiverIfTakerIsSeller,
        address takerCallback,
        bytes memory takerCallbackData
    ) external returns (uint256 buyerAssets, uint256 sellerAssets);

    function toMarket(bytes32 id) external view returns (Market memory);

    function isAuthorized(address authorizer, address authorized) external view returns (bool);

    function setIsAuthorized(address authorized, bool newIsAuthorized, address onBehalf) external;

    function credit(bytes32 id, address user) external view returns (uint256);

    function debt(bytes32 id, address user) external view returns (uint256);

    function continuousFee(bytes32 id) external view returns (uint256);

    function settlementFee(bytes32 id, uint256 timeToMaturity) external view returns (uint256);
}
