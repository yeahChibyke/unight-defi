// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "./IMidnight.sol";

/// @notice Boundary for contracts that authorize Midnight offers.
interface IMidnightRatifier {
    /// @notice Returns Midnight's success sentinel when an offer is authorized.
    /// @param offer Offer being checked.
    /// @param ratifierData Authorization data supplied with the offer.
    /// @param taker Address attempting to take the offer.
    function isRatified(IMidnight.Offer memory offer, bytes memory ratifierData, address taker)
        external
        returns (bytes32);
}
