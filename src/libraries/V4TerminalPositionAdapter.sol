// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PositionInfo, PositionInfoLibrary} from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IDormancyOracle} from "../interfaces/IDormancyOracle.sol";
import {V4LiquidityMath} from "./V4LiquidityMath.sol";

/// @title Uniswap v4 Terminal Position Adapter
/// @notice Restricts a v4 position unwind to the loan token when the position
///         is demonstrably terminal and historically dormant.
/// @dev This is an internal library, so PositionManager calls execute with the
///      UnightAccount as the caller and the account remains the NFT owner.
library V4TerminalPositionAdapter {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using PositionInfoLibrary for PositionInfo;
    using StateLibrary for IPoolManager;

    /// @notice Live position and terminal-principal observation.
    struct Snapshot {
        PoolKey key;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint160 sqrtPriceX96;
        bool loanIsCurrency0;
        uint256 terminalPrincipal;
    }

    /// @notice Immutable dependencies and policy parameters used by the adapter.
    struct Config {
        IPositionManager positionManager;
        IPoolManager poolManager;
        IDormancyOracle dormancyOracle;
        uint256 positionId;
        bytes32 expectedPoolId;
        address loanToken;
        uint24 tickBuffer;
        uint32 minimumDwell;
    }

    error PositionNotOwned();
    error WrongPool();
    error LoanTokenNotTerminal();
    error PositionNotTerminal();
    error InsufficientTerminalPrincipal();
    error DormancyNotProven();
    error InvalidTicks();
    error InvalidOutput();

    /// @notice Reads and validates the current terminal state of the position.
    /// @param config PositionManager, pool, oracle, identity, and safety parameters.
    /// @return result Position metadata and the principal available on the terminal side.
    function snapshot(Config memory config) internal view returns (Snapshot memory result) {
        if (IERC721(address(config.positionManager)).ownerOf(config.positionId) == address(0)) {
            revert PositionNotOwned();
        }
        if (IERC721(address(config.positionManager)).ownerOf(config.positionId) != address(this)) {
            revert PositionNotOwned();
        }

        PositionInfo info;
        (result.key, info) = config.positionManager.getPoolAndPositionInfo(config.positionId);
        PoolId poolId = result.key.toId();
        if (PoolId.unwrap(poolId) != config.expectedPoolId) revert WrongPool();
        if (
            Currency.unwrap(result.key.currency0) != config.loanToken
                && Currency.unwrap(result.key.currency1) != config.loanToken
        ) {
            revert LoanTokenNotTerminal();
        }

        result.tickLower = info.tickLower();
        result.tickUpper = info.tickUpper();
        if (result.tickLower >= result.tickUpper) revert InvalidTicks();
        result.liquidity = config.positionManager.getPositionLiquidity(config.positionId);
        int24 currentTick;
        (result.sqrtPriceX96, currentTick,,) = config.poolManager.getSlot0(poolId);

        bool below = int256(currentTick) <= int256(result.tickLower) - int256(uint256(config.tickBuffer));
        bool above = int256(currentTick) >= int256(result.tickUpper) + int256(uint256(config.tickBuffer));
        if (below == above) revert PositionNotTerminal();

        result.loanIsCurrency0 = below;
        Currency terminalCurrency = below ? result.key.currency0 : result.key.currency1;
        if (Currency.unwrap(terminalCurrency) != config.loanToken) revert LoanTokenNotTerminal();

        if (address(config.dormancyOracle) == address(0)) revert DormancyNotProven();
        if (!config.dormancyOracle
                .isDormant(
                    PoolId.unwrap(poolId), result.tickLower, result.tickUpper, config.tickBuffer, config.minimumDwell
                )) revert DormancyNotProven();

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(result.tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(result.tickUpper);
        result.terminalPrincipal = below
            ? V4LiquidityMath.amount0ForLiquidity(sqrtLower, sqrtUpper, result.liquidity)
            : V4LiquidityMath.amount1ForLiquidity(sqrtLower, sqrtUpper, result.liquidity);
    }

    /// @notice Removes enough terminal liquidity to fund a Midnight settlement.
    /// @dev Executes only `DECREASE_LIQUIDITY` followed by `TAKE_PAIR`; no swap,
    ///      arbitrary hook data, or arbitrary recipient is accepted.
    /// @param config PositionManager, pool, oracle, identity, and safety parameters.
    /// @param requiredAmount Minimum loan-token amount needed by Midnight.
    /// @param deadline PositionManager deadline for the liquidity mutation.
    /// @return principalRemoved Principal represented by the liquidity removed.
    function removeForFunding(Config memory config, uint256 requiredAmount, uint256 deadline)
        internal
        returns (uint256 principalRemoved)
    {
        Snapshot memory position = snapshot(config);
        if (position.terminalPrincipal < requiredAmount) revert InsufficientTerminalPrincipal();

        uint160 sqrtLower = TickMath.getSqrtPriceAtTick(position.tickLower);
        uint160 sqrtUpper = TickMath.getSqrtPriceAtTick(position.tickUpper);
        uint128 liquidityToRemove = position.loanIsCurrency0
            ? V4LiquidityMath.liquidityForAmount0(sqrtLower, sqrtUpper, requiredAmount)
            : V4LiquidityMath.liquidityForAmount1(sqrtLower, sqrtUpper, requiredAmount);
        if (liquidityToRemove == 0) liquidityToRemove = 1;
        if (liquidityToRemove > position.liquidity) liquidityToRemove = position.liquidity;

        principalRemoved = position.loanIsCurrency0
            ? V4LiquidityMath.amount0ForLiquidity(sqrtLower, sqrtUpper, liquidityToRemove)
            : V4LiquidityMath.amount1ForLiquidity(sqrtLower, sqrtUpper, liquidityToRemove);
        if (principalRemoved < requiredAmount && liquidityToRemove < position.liquidity) {
            unchecked {
                ++liquidityToRemove;
            }
            principalRemoved = position.loanIsCurrency0
                ? V4LiquidityMath.amount0ForLiquidity(sqrtLower, sqrtUpper, liquidityToRemove)
                : V4LiquidityMath.amount1ForLiquidity(sqrtLower, sqrtUpper, liquidityToRemove);
        }
        if (principalRemoved < requiredAmount) revert InsufficientTerminalPrincipal();

        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        if (requiredAmount > type(uint128).max) revert InvalidOutput();
        uint128 requiredAmount128 = uint128(requiredAmount);
        uint128 amount0Min = position.loanIsCurrency0 ? requiredAmount128 : uint128(0);
        uint128 amount1Min = position.loanIsCurrency0 ? uint128(0) : requiredAmount128;
        params[0] = abi.encode(config.positionId, liquidityToRemove, amount0Min, amount1Min, bytes(""));
        params[1] = abi.encode(position.key.currency0, position.key.currency1, address(this));

        uint256 beforeBalance = IERC20(config.loanToken).balanceOf(address(this));
        config.positionManager.modifyLiquidities(abi.encode(actions, params), deadline);
        uint256 afterBalance = IERC20(config.loanToken).balanceOf(address(this));
        if (afterBalance < beforeBalance || afterBalance - beforeBalance < requiredAmount) {
            revert InvalidOutput();
        }
    }
}
