// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {UnightBidRatifier} from "../src/UnightBidRatifier.sol";
import {UnightAccount} from "../src/UnightAccount.sol";
import {IMidnight} from "../src/interfaces/IMidnight.sol";
import {IMidnightRatifier} from "../src/interfaces/IMidnightRatifier.sol";
import {BaseForkHarness} from "./BaseForkHarness.sol";

/// @notice Fork tests for UnightBidRatifier wiring and callback authority.
/// @dev The live EcrecoverRatifier is used as the configured base ratifier.
contract BaseForkRatifierTest is BaseForkHarness {
    address internal constant BASE_RATIFIER = 0xd6e70365C8E8DDa9a4ca662C07bbE663b017755E;

    /// @notice Confirms the ratifier stores the live Midnight dependencies.
    function testRatifierStoresLiveMidnightDependencies() public {
        UnightBidRatifier ratifier = new UnightBidRatifier(midnight, IMidnightRatifier(BASE_RATIFIER), account);

        assertEq(address(ratifier.midnight()), MIDNIGHT);
        assertEq(address(ratifier.baseRatifier()), BASE_RATIFIER);
        assertEq(address(ratifier.account()), address(account));
    }

    /// @notice Rejects direct ratifier calls that do not originate from Midnight.
    function testRatifierRejectsDirectNonMidnightInvocation() public {
        UnightBidRatifier ratifier = new UnightBidRatifier(midnight, IMidnightRatifier(BASE_RATIFIER), account);
        IMidnight.Offer memory offer;

        vm.expectRevert(UnightBidRatifier.NotMidnight.selector);
        ratifier.isRatified(offer, bytes(""), address(0xCAFE));
    }

    /// @notice Rejects bid-context registration from an unconfigured caller.
    function testAccountRejectsBidContextFromUnexpectedRatifier() public {
        IMidnight.Market memory market = terminalMarket();
        uint256 policyNonce = account.policyNonce();
        uint256 positionEpoch = account.positionEpoch();
        bytes memory callbackData = abi.encode(policyNonce, positionEpoch, 101e6);
        vm.expectRevert(UnightAccount.CallbackRejected.selector);
        vm.prank(address(0xBEEF));
        account.registerBidContext(
            keccak256("unexpected-ratifier"), market, address(0xCAFE), 100e6, block.timestamp + 1 hours, callbackData
        );
    }
}
