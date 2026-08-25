// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UnightAccount} from "../src/UnightAccount.sol";
import {IMidnight} from "../src/interfaces/IMidnight.sol";
import {BaseForkHarness} from "./BaseForkHarness.sol";

/// @notice Fork tests for authenticated Midnight callback validation and funding.
/// @dev These tests invoke the live Midnight address directly; they do not claim
///      to execute a complete live {IMidnight.take} settlement.
contract BaseForkCallbackTest is BaseForkHarness {
    uint256 internal constant BUYER_ASSETS = 100e6;
    uint256 internal constant MIN_UNITS = 101e6;

    /// @notice Registers a maker-bid callback context for the current policy.
    /// @param maxAssets Maximum gross buyer assets accepted by the context.
    /// @param deadline Latest callback timestamp.
    /// @param data Policy, position-epoch, and minimum-unit commitments.
    function registerContext(uint256 maxAssets, uint256 deadline, bytes memory data) internal {
        account.registerBidContext(
            keccak256("fork-callback"), terminalMarket(), address(0xCAFE), uint128(maxAssets), deadline, data
        );
    }

    /// @notice Encodes callback data matching the current account epochs.
    /// @param minUnits Minimum credit units accepted by the callback.
    /// @return data Encoded callback commitments.
    function validData(uint256 minUnits) internal view returns (bytes memory) {
        return abi.encode(account.policyNonce(), account.positionEpoch(), minUnits);
    }

    /// @notice Rejects callback calls from any address other than Midnight.
    function testCallbackRejectsWrongCaller() public {
        bytes memory data = validData(MIN_UNITS);
        IMidnight.Market memory market = terminalMarket();
        vm.expectRevert(UnightAccount.CallbackRejected.selector);
        vm.prank(address(0xBEEF));
        account.onBuy(MARKET_ID, market, BUYER_ASSETS, MIN_UNITS, 0, LP_OWNER, data);
    }

    /// @notice Rejects a Midnight callback when no execution context is active.
    function testCallbackRejectsWithoutActiveContext() public {
        bytes memory data = validData(MIN_UNITS);
        IMidnight.Market memory market = terminalMarket();
        vm.expectRevert(UnightAccount.CallbackRejected.selector);
        vm.prank(MIDNIGHT);
        account.onBuy(MARKET_ID, market, BUYER_ASSETS, MIN_UNITS, 0, LP_OWNER, data);
    }

    /// @notice Rejects gross funding above the registered context limit.
    function testCallbackRejectsBuyerAssetsAboveContextLimit() public {
        setPoolTick(BELOW_TERMINAL_TICK);
        bytes memory data = validData(MIN_UNITS);
        registerContext(BUYER_ASSETS, block.timestamp + 1 hours, data);
        IMidnight.Market memory market = terminalMarket();

        vm.expectRevert(UnightAccount.CallbackRejected.selector);
        vm.prank(MIDNIGHT);
        account.onBuy(MARKET_ID, market, BUYER_ASSETS + 1, MIN_UNITS, 0, LP_OWNER, data);
    }

    /// @notice Rejects a settlement reporting fewer units than committed.
    function testCallbackRejectsUnitsBelowMinimum() public {
        setPoolTick(BELOW_TERMINAL_TICK);
        bytes memory data = validData(MIN_UNITS);
        registerContext(BUYER_ASSETS, block.timestamp + 1 hours, data);
        IMidnight.Market memory market = terminalMarket();

        vm.expectRevert(UnightAccount.CallbackRejected.selector);
        vm.prank(MIDNIGHT);
        account.onBuy(MARKET_ID, market, BUYER_ASSETS, MIN_UNITS - 1, 0, LP_OWNER, data);
    }

    /// @notice Rejects credit being assigned to an unexpected buyer.
    function testCallbackRejectsWrongBuyer() public {
        setPoolTick(BELOW_TERMINAL_TICK);
        bytes memory data = validData(MIN_UNITS);
        registerContext(BUYER_ASSETS, block.timestamp + 1 hours, data);
        IMidnight.Market memory market = terminalMarket();

        vm.expectRevert(UnightAccount.CallbackRejected.selector);
        vm.prank(MIDNIGHT);
        account.onBuy(MARKET_ID, market, BUYER_ASSETS, MIN_UNITS, 0, address(0xB0B), data);
    }

    /// @notice Rejects callback data that differs from the registered context.
    function testCallbackRejectsWrongCallbackData() public {
        setPoolTick(BELOW_TERMINAL_TICK);
        bytes memory data = validData(MIN_UNITS);
        registerContext(BUYER_ASSETS, block.timestamp + 1 hours, data);
        IMidnight.Market memory market = terminalMarket();

        vm.expectRevert(UnightAccount.CallbackRejected.selector);
        vm.prank(MIDNIGHT);
        account.onBuy(MARKET_ID, market, BUYER_ASSETS, MIN_UNITS, 0, LP_OWNER, abi.encode(uint256(1)));
    }

    /// @notice Removes terminal liquidity and accounts for gross buyer assets.
    /// @dev The call verifies exact allowance, mode accounting, and context
    ///      clearing after the live Midnight-address callback returns.
    function testSuccessfulCallbackUpdatesOnlyGrossBuyerAssetAccounting() public {
        setPoolTick(BELOW_TERMINAL_TICK);
        bytes memory data = validData(MIN_UNITS);
        registerContext(BUYER_ASSETS, block.timestamp + 1 hours, data);
        IMidnight.Market memory market = terminalMarket();
        uint256 beforeLiquidity = positionManager.getPositionLiquidity(POSITION_ID);

        vm.prank(MIDNIGHT);
        account.onBuy(MARKET_ID, market, BUYER_ASSETS, MIN_UNITS, 0, LP_OWNER, data);

        assertEq(account.committedBuyerAssets(), BUYER_ASSETS);
        assertEq(account.bidBoardBuyerAssets(), BUYER_ASSETS);
        assertEq(account.autoLendBuyerAssets(), 0);
        assertLt(positionManager.getPositionLiquidity(POSITION_ID), beforeLiquidity);
        assertEq(usdc.allowance(address(account), MIDNIGHT), BUYER_ASSETS);
        assertEq(uint256(account.executionContext().state), 0);
    }
}
