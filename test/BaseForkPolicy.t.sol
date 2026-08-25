// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {UnightAccount} from "../src/UnightAccount.sol";
import {UnightPolicy} from "../src/libraries/UnightTypes.sol";
import {BaseForkHarness} from "./BaseForkHarness.sol";

/// @notice Fork tests for policy, ownership, executor, and NFT lifecycle rules.
contract BaseForkPolicyTest is BaseForkHarness {
    /// @notice Disabling a policy increments its nonce and removes bid capacity.
    function testOwnerCanDisablePolicyAndCapacityBecomesZero() public {
        vm.prank(LP_OWNER);
        account.disablePolicy();

        assertEq(account.policyNonce(), 2);
        assertEq(account.remainingBidCapacity(), 0);
    }

    /// @notice Rejects policy and lifecycle changes from a non-owner.
    function testNonOwnerCannotChangePolicyOrClose() public {
        vm.expectRevert(UnightAccount.NotOwner.selector);
        account.disablePolicy();

        vm.expectRevert(UnightAccount.NotOwner.selector);
        account.close();
    }

    /// @notice Rejects an Auto-Lend cap larger than the global cap.
    function testPolicyRejectsAutoCapAboveGlobalCap() public {
        UnightPolicy memory invalid = defaultPolicy();
        invalid.autoLendCap = invalid.globalCap + 1;

        vm.expectRevert(UnightAccount.InvalidPolicy.selector);
        vm.prank(LP_OWNER);
        account.setPolicy(invalid);
    }

    /// @notice Allows the LP to add and remove an Auto-Lend executor.
    function testExecutorCanBeAddedAndRemoved() public {
        address executor = address(0xE1);

        vm.prank(LP_OWNER);
        account.setExecutor(executor, true);
        assertTrue(account.isExecutor(executor));

        vm.prank(LP_OWNER);
        account.setExecutor(executor, false);
        assertFalse(account.isExecutor(executor));
    }

    /// @notice Prevents NFT withdrawal while the account is still open.
    function testPositionCannotBeWithdrawnBeforeClose() public {
        vm.expectRevert(UnightAccount.InvalidPolicy.selector);
        vm.prank(LP_OWNER);
        account.withdrawPosition();
    }

    /// @notice Closes the account and returns the controlled NFT to the LP.
    function testCloseRevokesAuthorizationAndAllowsNftRecovery() public {
        vm.prank(LP_OWNER);
        account.close();

        assertTrue(account.closed());
        assertEq(account.remainingBidCapacity(), 0);

        vm.prank(LP_OWNER);
        account.withdrawPosition();
        assertEq(positionNft.ownerOf(POSITION_ID), LP_OWNER);
    }

    /// @notice Rejects ERC-721 deliveries from an address other than PositionManager.
    function testReceiverRejectsNonPositionManager() public {
        vm.expectRevert(UnightAccount.NotPositionManager.selector);
        account.onERC721Received(address(this), LP_OWNER, POSITION_ID, bytes(""));
    }

    /// @notice Rejects an NFT ID other than the account's configured position.
    function testReceiverRejectsWrongPositionId() public {
        vm.expectRevert(UnightAccount.WrongPosition.selector);
        vm.prank(POSITION_MANAGER);
        account.onERC721Received(address(this), LP_OWNER, POSITION_ID + 1, bytes(""));
    }
}
