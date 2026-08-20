// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "../interfaces/IMidnight.sol";

library MarketId {
    /// @dev Internal struct identity for binding one callback to one market.
    ///      Account policy validation compares against Midnight.toMarket(id),
    ///      so this helper is not treated as the external market-id oracle.
    function hash(IMidnight.Market memory market) internal pure returns (bytes32) {
        return keccak256(abi.encode(market));
    }
}
