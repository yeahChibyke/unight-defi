// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title Midnight SetterRatifier boundary
/// @notice Minimal interface for the deployed SetterRatifier used by fork tests.
interface ISetterRatifier {
    /// @notice Authorizes a Merkle root for its maker.
    function setIsRootRatified(address maker, bytes32 root, bool newIsRootRatified) external;

    /// @notice Returns whether a maker has authorized a Merkle root.
    function isRootRatified(address maker, bytes32 root) external view returns (bool);
}
