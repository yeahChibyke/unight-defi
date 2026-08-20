// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Historical price/dwell boundary used before an LP position is
///         treated as a terminal one-sided funding source.
interface IDormancyOracle {
    function isDormant(bytes32 poolId, int24 tickLower, int24 tickUpper, uint24 tickBuffer, uint32 minimumDwell)
        external
        view
        returns (bool);
}
