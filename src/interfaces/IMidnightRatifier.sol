// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "./IMidnight.sol";

interface IMidnightRatifier {
    function isRatified(IMidnight.Offer memory offer, bytes memory ratifierData, address taker)
        external
        returns (bytes32);
}
