// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "./IMidnight.sol";

/// @notice Narrow account surface used by the maker-bid ratifier.
interface IUnightAccount {
    /// @notice LP owner of the account.
    function owner() external view returns (address);

    /// @notice Market selected by the account's current policy.
    function marketId() external view returns (bytes32);

    /// @notice Registers an offer context immediately before Midnight's callback.
    /// @param offerHash Hash of the exact offer being taken.
    /// @param market Market metadata embedded in the offer.
    /// @param taker Address taking the offer.
    /// @param maxAssets Offer-declared maximum buyer assets.
    /// @param deadline Offer expiry used for the callback deadline.
    /// @param callbackData Encoded account policy and position commitments.
    function registerBidContext(
        bytes32 offerHash,
        IMidnight.Market calldata market,
        address taker,
        uint128 maxAssets,
        uint256 deadline,
        bytes calldata callbackData
    ) external;
}
