// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";

/// @notice Arithmetic helpers for converting v4 concentrated liquidity to token amounts.
library V4LiquidityMath {
    /// @notice Returns currency0 represented by liquidity across a price range.
    /// @param sqrtPriceAX96 First range boundary in Q96 format.
    /// @param sqrtPriceBX96 Second range boundary in Q96 format.
    /// @param liquidity Position liquidity.
    function amount0ForLiquidity(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        internal
        pure
        returns (uint256)
    {
        (uint160 lower, uint160 upper) = _sort(sqrtPriceAX96, sqrtPriceBX96);
        return FullMath.mulDiv(uint256(liquidity) << 96, upper - lower, upper) / lower;
    }

    /// @notice Returns currency1 represented by liquidity across a price range.
    /// @param sqrtPriceAX96 First range boundary in Q96 format.
    /// @param sqrtPriceBX96 Second range boundary in Q96 format.
    /// @param liquidity Position liquidity.
    function amount1ForLiquidity(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        internal
        pure
        returns (uint256)
    {
        (uint160 lower, uint160 upper) = _sort(sqrtPriceAX96, sqrtPriceBX96);
        return FullMath.mulDiv(liquidity, upper - lower, FixedPoint96.Q96);
    }

    /// @notice Returns the liquidity corresponding to a currency0 amount.
    /// @param sqrtPriceAX96 First range boundary in Q96 format.
    /// @param sqrtPriceBX96 Second range boundary in Q96 format.
    /// @param amount0 Currency0 amount.
    function liquidityForAmount0(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount0)
        internal
        pure
        returns (uint128)
    {
        (uint160 lower, uint160 upper) = _sort(sqrtPriceAX96, sqrtPriceBX96);
        uint256 intermediate = FullMath.mulDiv(lower, upper, FixedPoint96.Q96);
        uint256 liquidity = FullMath.mulDiv(amount0, intermediate, upper - lower);
        require(liquidity <= type(uint128).max, "UNIGHT_LIQUIDITY_OVERFLOW");
        return uint128(liquidity);
    }

    /// @notice Returns the liquidity corresponding to a currency1 amount.
    /// @param sqrtPriceAX96 First range boundary in Q96 format.
    /// @param sqrtPriceBX96 Second range boundary in Q96 format.
    /// @param amount1 Currency1 amount.
    function liquidityForAmount1(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1)
        internal
        pure
        returns (uint128)
    {
        (uint160 lower, uint160 upper) = _sort(sqrtPriceAX96, sqrtPriceBX96);
        uint256 liquidity = FullMath.mulDiv(amount1, FixedPoint96.Q96, upper - lower);
        require(liquidity <= type(uint128).max, "UNIGHT_LIQUIDITY_OVERFLOW");
        return uint128(liquidity);
    }

    /// @dev Orders two square-root prices from lower to upper.
    function _sort(uint160 a, uint160 b) private pure returns (uint160 lower, uint160 upper) {
        if (a < b) return (a, b);
        return (b, a);
    }
}
