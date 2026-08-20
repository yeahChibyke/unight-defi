// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "../interfaces/IMidnight.sol";

/// @notice Internal market-struct hashing helper.
library MarketId {
    /// @dev Internal struct identity for binding one callback to one market.
    ///      Account policy validation compares against Midnight.toMarket(id),
    ///      so this helper is not treated as the external market-id oracle.
    /// @notice Hashes market metadata for same-transaction callback binding.
    /// @param market Market metadata to hash.
    /// @return identity Keccak hash of the ABI-encoded market struct.
    function hash(IMidnight.Market memory market) internal pure returns (bytes32 identity) {
        return keccak256(abi.encode(market));
    }
}
