// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "./interfaces/IMidnight.sol";
import {IMidnightRatifier} from "./interfaces/IMidnightRatifier.sol";
import {IUnightAccount} from "./interfaces/IUnightAccount.sol";

/// @title Unight Bid Ratifier
/// @notice Adapter that composes Midnight's base authorization ratifier with
///         Unight's dynamic LP-account checks.
/// @dev The base ratifier remains responsible for maker authorization. This
///      adapter additionally registers the exact offer before Midnight invokes
///      the account callback, giving the callback an unforgeable offer context.
contract UnightBidRatifier is IMidnightRatifier {
    bytes32 private constant CALLBACK_SUCCESS = keccak256("morpho.midnight.callbackSuccess");

    IMidnight public immutable midnight;
    IMidnightRatifier public immutable baseRatifier;
    IUnightAccount public immutable account;

    error NotMidnight();
    error BaseRatificationFailed();
    error OfferRejected();

    /// @param midnight_ Canonical Midnight protocol that is allowed to call this ratifier.
    /// @param baseRatifier_ Existing ratifier responsible for maker authorization.
    /// @param account_ Unight account whose maker offer this ratifier protects.
    constructor(IMidnight midnight_, IMidnightRatifier baseRatifier_, IUnightAccount account_) {
        require(
            address(midnight_) != address(0) && address(baseRatifier_) != address(0) && address(account_) != address(0),
            "UNIGHT_ZERO_ADDRESS"
        );
        midnight = midnight_;
        baseRatifier = baseRatifier_;
        account = account_;
    }

    /// @notice Validates a maker bid and registers its exact callback context.
    /// @dev The call must originate from Midnight. The base ratifier runs first;
    ///      only then is the offer bound to the account before callback execution.
    /// @param offer Midnight offer being ratified.
    /// @param ratifierData Authorization data forwarded to the base ratifier.
    /// @param taker Address taking the maker offer.
    /// @return success Midnight's callback-success sentinel.
    function isRatified(IMidnight.Offer memory offer, bytes memory ratifierData, address taker)
        external
        returns (bytes32)
    {
        if (msg.sender != address(midnight)) revert NotMidnight();
        if (baseRatifier.isRatified(offer, ratifierData, taker) != CALLBACK_SUCCESS) {
            revert BaseRatificationFailed();
        }
        if (
            !offer.buy || offer.maker != account.owner() || offer.callback != address(account)
                || offer.ratifier != address(this) || offer.maxAssets == 0 || offer.expiry > offer.market.maturity
        ) revert OfferRejected();

        account.registerBidContext(
            keccak256(abi.encode(offer)), offer.market, taker, offer.maxAssets, offer.expiry, offer.callbackData
        );
        return CALLBACK_SUCCESS;
    }
}
