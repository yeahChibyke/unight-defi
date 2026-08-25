// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {V4TerminalPositionAdapter} from "../src/libraries/V4TerminalPositionAdapter.sol";
import {UnightPolicy} from "../src/libraries/UnightTypes.sol";
import {BaseForkHarness} from "./BaseForkHarness.sol";

/// @notice Fork tests for terminal-position detection and dormancy checks.
/// @dev Uses the live Base v4 position while moving only fork-local pool state.
contract BaseForkAdapterTest is BaseForkHarness {
    /// @notice Rejects capacity while the position remains inside its range.
    function testActivePositionHasNoTerminalCapacity() public {
        vm.expectRevert(V4TerminalPositionAdapter.PositionNotTerminal.selector);
        account.remainingCapacity();
    }

    /// @notice Accepts a below-range position when USDC is the terminal asset.
    /// @dev The reserve is disabled here so the test observes positive capacity.
    function testBelowRangeUsesLoanCurrency0AndReportsPrincipal() public {
        setPoolTick(BELOW_TERMINAL_TICK);
        UnightPolicy memory policy = defaultPolicy();
        policy.reactivationReserve = 0;
        vm.prank(LP_OWNER);
        account.setPolicy(policy);

        uint256 capacity = account.remainingCapacity();
        assertGt(capacity, 0);
    }

    /// @notice Rejects an above-range position because cbBTC, not USDC, is terminal.
    function testAboveRangeRejectsBecauseLoanTokenIsNotTerminal() public {
        setPoolTick(ABOVE_TERMINAL_TICK);

        vm.expectRevert(V4TerminalPositionAdapter.LoanTokenNotTerminal.selector);
        account.remainingCapacity();
    }

    /// @notice Rejects a price that has not crossed the configured tick buffer.
    function testTickBufferProtectsNearBoundary() public {
        setPoolTick(LOWER_TICK - 99);

        vm.expectRevert(V4TerminalPositionAdapter.PositionNotTerminal.selector);
        account.remainingCapacity();
    }

    /// @notice Rejects the exact range boundary when the buffer is nonzero.
    function testTickAtLowerBoundaryIsNotTerminalWithBuffer() public {
        setPoolTick(LOWER_TICK);

        vm.expectRevert(V4TerminalPositionAdapter.PositionNotTerminal.selector);
        account.remainingCapacity();
    }

    /// @notice Rejects terminal funding when historical dormancy is not proven.
    function testDormancyOracleCanDisableFunding() public {
        setPoolTick(BELOW_TERMINAL_TICK);
        dormancyOracle.setDormant(false);

        vm.expectRevert(V4TerminalPositionAdapter.DormancyNotProven.selector);
        account.remainingCapacity();
    }
}
