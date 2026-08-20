// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "./IMidnight.sol";

/// @notice Callback invoked by Midnight after a buy-side settlement is priced.
interface IMidnightBuyCallback {
    /// @notice Validates the settlement and returns Midnight's success sentinel.
    /// @param id Market identifier for the settlement.
    /// @param market Canonical market metadata.
    /// @param buyerAssets Gross assets required from the buyer.
    /// @param units Credit units exchanged.
    /// @param pendingFeeIncrease Fee increase created by the settlement.
    /// @param buyer Address receiving the purchased credit.
    /// @param data Taker callback data supplied to Midnight.take.
    function onBuy(
        bytes32 id,
        IMidnight.Market memory market,
        uint256 buyerAssets,
        uint256 units,
        uint256 pendingFeeIncrease,
        address buyer,
        bytes memory data
    ) external returns (bytes32);
}
