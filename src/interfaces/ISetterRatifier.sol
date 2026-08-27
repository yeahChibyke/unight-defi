// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMidnight} from "./IMidnight.sol";

/// @title Midnight SetterRatifier boundary
/// @notice Minimal interface for the deployed SetterRatifier used by fork tests.
interface ISetterRatifier {
    /// @notice Authorizes a Merkle root for its maker.
    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) external;

    /// @notice Returns whether a maker has authorized a Merkle root.
    function isRootRatified(address maker, bytes32 root) external view returns (bool);

    /// @notice Validates Merkle proof data for an offer and its maker root.
    function isRatified(IMidnight.Offer memory offer, bytes memory ratifierData, address taker)
        external
        view
        returns (bytes32);
}
