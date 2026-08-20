// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Historical price/dwell boundary used before an LP position is treated
///         as a terminal one-sided funding source.
interface IDormancyOracle {
    /// @notice Reports whether a position has remained safely terminal for the required dwell.
    /// @param poolId Uniswap v4 pool identity.
    /// @param tickLower Position lower tick.
    /// @param tickUpper Position upper tick.
    /// @param tickBuffer Safety buffer beyond the position boundary.
    /// @param minimumDwell Required historical dwell interval.
    /// @return dormant True when the oracle accepts the terminality condition.
    function isDormant(bytes32 poolId, int24 tickLower, int24 tickUpper, uint24 tickBuffer, uint32 minimumDwell)
        external
        view
        returns (bool);
}
