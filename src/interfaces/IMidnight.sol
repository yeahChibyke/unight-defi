// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Midnight Protocol Boundary
/// @notice Minimal, locally pinned interface used by Unight's onchain contracts.
/// @dev Keep this file synchronized with the deployed Midnight interface before
///      production deployment. It is deliberately local because this repository
///      does not vendor Midnight's Solidity package yet.
interface IMidnight {
    /// @notice Risk and oracle parameters for one collateral type.
    struct CollateralParams {
        address token;
        uint256 lltv;
        uint256 liquidationCursor;
        address oracle;
    }

    /// @notice Immutable configuration identifying a Midnight market.
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

    /// @notice Signed or ratified order consumed by {take}.
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

    /// @notice Aggregate state returned by implementations that expose market state.
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

    /// @notice Settles an offer and optionally invokes a taker callback.
    function take(
        Offer memory offer,
        bytes memory ratifierData,
        uint256 units,
        address taker,
        address receiverIfTakerIsSeller,
        address takerCallback,
        bytes memory takerCallbackData
    ) external returns (uint256 buyerAssets, uint256 sellerAssets);

    /// @notice Resolves a market identifier to its canonical market metadata.
    function toMarket(bytes32 id) external view returns (Market memory);

    /// @notice Returns whether `authorized` may act on behalf of `authorizer`.
    function isAuthorized(address authorizer, address authorized) external view returns (bool);

    /// @notice Changes an authorization on behalf of `onBehalf`.
    function setIsAuthorized(address authorized, bool newIsAuthorized, address onBehalf) external;

    /// @notice Supplies collateral to a market on behalf of an account.
    function supplyCollateral(Market memory market, uint256 collateralIndex, uint256 assets, address onBehalf) external;

    /// @notice Returns the market tick spacing used to validate offer ticks.
    function tickSpacing(bytes32 id) external view returns (uint256);

    /// @notice Returns a user's credit balance in a market.
    function credit(bytes32 id, address user) external view returns (uint256);

    /// @notice Returns a user's debt balance in a market.
    function debt(bytes32 id, address user) external view returns (uint256);

    /// @notice Returns the current continuous fee for a market.
    function continuousFee(bytes32 id) external view returns (uint256);

    /// @notice Returns the settlement fee at a specified time to maturity.
    function settlementFee(bytes32 id, uint256 timeToMaturity) external view returns (uint256);
}
