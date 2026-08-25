// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "../src/interfaces/IMidnight.sol";

/// @notice Test-only reproduction of Midnight's deployed HashLib offer hash.
library ForkOfferHash {
    /// @notice Returns the deployed HashLib EIP-712 struct hash for an offer.
    /// @dev The result is the leaf hash authorized by SetterRatifier. The
    ///      assembly encoder mirrors HashLib's 16-word static ABI encoding.
    /// @param offer Offer to hash, including its nested market metadata.
    /// @return offerHash HashLib-compatible offer leaf digest.
    function hashOffer(IMidnight.Offer memory offer) internal pure returns (bytes32) {
        bytes32 marketHash = _hashMarket(offer.market);
        bytes32 callbackDataHash = keccak256(offer.callbackData);
        bytes32 typeHash = 0x9905214264a9fb7b6cc1b0e33db7a04687c6e4185a84755d29914314aa9d8906;
        bytes32 result;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(add(ptr, 0x00), typeHash)
            mstore(add(ptr, 0x20), marketHash)
            mstore(add(ptr, 0x40), mload(add(offer, 0x20)))
            mstore(add(ptr, 0x60), mload(add(offer, 0x40)))
            mstore(add(ptr, 0x80), mload(add(offer, 0x60)))
            mstore(add(ptr, 0xa0), mload(add(offer, 0x80)))
            mstore(add(ptr, 0xc0), mload(add(offer, 0xa0)))
            mstore(add(ptr, 0xe0), mload(add(offer, 0xc0)))
            mstore(add(ptr, 0x100), mload(add(offer, 0xe0)))
            mstore(add(ptr, 0x120), callbackDataHash)
            mstore(add(ptr, 0x140), mload(add(offer, 0x120)))
            mstore(add(ptr, 0x160), mload(add(offer, 0x140)))
            mstore(add(ptr, 0x180), mload(add(offer, 0x160)))
            mstore(add(ptr, 0x1a0), mload(add(offer, 0x180)))
            mstore(add(ptr, 0x1c0), mload(add(offer, 0x1a0)))
            mstore(add(ptr, 0x1e0), mload(add(offer, 0x1c0)))
            result := keccak256(ptr, 0x200)
        }
        return result;
    }

    /// @dev Hashes collateral parameters and the containing market as defined
    ///      by Midnight's deployed HashLib type hashes.
    /// @param market Market metadata nested in the offer.
    /// @return marketHash HashLib-compatible market struct digest.
    function _hashMarket(IMidnight.Market memory market) private pure returns (bytes32) {
        bytes32[] memory collateralHashes = new bytes32[](market.collateralParams.length);
        for (uint256 i; i < collateralHashes.length; ++i) {
            IMidnight.CollateralParams memory collateral = market.collateralParams[i];
            collateralHashes[i] = keccak256(
                abi.encode(
                    0x39ed3f928d24fd00574b1a02aba9c2483abcf5d9a3a366118c9a5aa29885b841,
                    collateral.token,
                    collateral.lltv,
                    collateral.liquidationCursor,
                    collateral.oracle
                )
            );
        }

        return keccak256(
            abi.encode(
                0x510b3862f3816a109c9340b76972e8a30984246be06e034ae12ed2934220391a,
                market.chainId,
                market.midnight,
                market.loanToken,
                keccak256(abi.encodePacked(collateralHashes)),
                market.maturity,
                market.rcfThreshold,
                market.enterGate,
                market.liquidatorGate
            )
        );
    }
}
