// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UnightAccount} from "../src/UnightAccount.sol";
import {UnightPolicy} from "../src/libraries/UnightTypes.sol";
import {IMidnight} from "../src/interfaces/IMidnight.sol";
import {BaseForkHarness} from "./BaseForkHarness.sol";

/// @title Base fork fuzz and invariant checks
/// @notice Exercises policy boundaries, lifecycle authorization, and callback
///         rollback against live Base v4, USDC, and Midnight deployments.
/// @dev The protocol contracts under test are deployed locally on a fresh fork;
///      their external v4, USDC, and Midnight dependencies are live fork state.
contract BaseForkFuzzTest is BaseForkHarness {
    /// @notice Fuzzes valid policy cap combinations and verifies the stored caps.
    function testFuzzValidPolicyCaps(uint128 globalCap, uint128 autoCap, uint128 bidCap) public {
        globalCap = uint128(bound(globalCap, 1e6, 1_000_000_000e6));
        autoCap = uint128(bound(autoCap, 0, globalCap));
        bidCap = uint128(bound(bidCap, 0, globalCap));

        UnightPolicy memory policy = defaultPolicy();
        policy.globalCap = globalCap;
        policy.autoLendCap = autoCap;
        policy.bidBoardCap = bidCap;

        vm.prank(LP_OWNER);
        account.setPolicy(policy);

        (bool ok, bytes memory data) = address(account).staticcall(abi.encodeWithSignature("policy()"));
        assertTrue(ok);
        UnightPolicy memory stored = abi.decode(data, (UnightPolicy));
        assertEq(stored.marketId, MARKET_ID);
        assertEq(stored.globalCap, globalCap);
        assertEq(stored.autoLendCap, autoCap);
        assertEq(stored.bidBoardCap, bidCap);
    }

    /// @notice Fuzzes invalid mode caps and verifies policy installation reverts.
    function testFuzzRejectsModeCapAboveGlobal(uint128 globalCap, uint128 excess, bool autoMode) public {
        globalCap = uint128(bound(globalCap, 1e6, 1_000_000_000e6));
        excess = uint128(bound(excess, 1, type(uint128).max - globalCap));

        UnightPolicy memory policy = defaultPolicy();
        policy.globalCap = globalCap;
        if (autoMode) policy.autoLendCap = globalCap + excess;
        else policy.bidBoardCap = globalCap + excess;

        vm.expectRevert(UnightAccount.InvalidPolicy.selector);
        vm.prank(LP_OWNER);
        account.setPolicy(policy);
    }

    /// @notice Fuzzes executor permission changes without changing accounting.
    function testFuzzExecutorIsolation(uint160 executorSeed, bool enabled) public {
        address executor = address(uint160(bound(executorSeed, 1, type(uint160).max)));
        uint256 nonce = account.policyNonce();
        uint256 committed = account.committedBuyerAssets();

        vm.prank(LP_OWNER);
        account.setExecutor(executor, enabled);

        assertEq(account.isExecutor(executor), enabled);
        assertEq(account.policyNonce(), nonce);
        assertEq(account.committedBuyerAssets(), committed);
    }

    /// @notice Fuzzes malformed callback commitments and verifies rollback.
    function testFuzzMalformedCallbackRollsBack(bytes32 suppliedData) public {
        UnightPolicy memory policy = defaultPolicy();
        policy.reactivationReserve = 0;
        policy.expiry = block.timestamp + 2 days;
        vm.prank(LP_OWNER);
        account.setPolicy(policy);
        uint256 committed = account.committedBuyerAssets();
        uint256 removed = account.v4PrincipalRemoved();

        _attemptMalformedCallback(suppliedData);

        assertEq(account.committedBuyerAssets(), committed);
        assertEq(account.v4PrincipalRemoved(), removed);
        assertEq(uint256(account.executionContext().state), uint256(UnightAccount.ExecutionState.MakerBid));
    }

    function _attemptMalformedCallback(bytes32 suppliedData) internal {
        setPoolTick(BELOW_TERMINAL_TICK);
        IMidnight.Market memory market = terminalMarket();
        bytes memory validData = abi.encode(account.policyNonce(), account.positionEpoch(), 1);
        account.registerBidContext(
            keccak256("fuzz-offer"), market, address(this), 1e6, block.timestamp + 1 hours, validData
        );
        vm.expectRevert();
        vm.prank(MIDNIGHT);
        account.onBuy(MARKET_ID, market, 1e6, 1, 0, LP_OWNER, abi.encode(suppliedData));
    }
}
