// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISetterRatifier} from "../src/interfaces/ISetterRatifier.sol";
import {IMidnight} from "../src/interfaces/IMidnight.sol";
import {UnightPolicy} from "../src/libraries/UnightTypes.sol";
import {BaseForkHarness} from "./BaseForkHarness.sol";
import {ForkOfferHash} from "./ForkOfferHash.sol";

/// @title Base fork Auto-Lend settlement tests
/// @notice Exercises one complete auto-lend settlement against live Midnight,
///         the deployed SetterRatifier, USDC, cbBTC, and Uniswap v4.
/// @dev The borrower is fork-local and receives cbBTC through Foundry's fork
///      balance helper. All protocol contracts and the LP position are live.
contract BaseForkAutoLendTest is BaseForkHarness {
    /// @dev Deployed Base SetterRatifier used to authorize the borrower offer.
    address internal constant SETTER_RATIFIER = 0x800B5F12A61B8198a5a6EfD794Cac6699B294d63;
    /// @dev Deployed Base cbBTC collateral token used by the selected market.
    address internal constant CB_BTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    /// @dev Fork-local borrower whose collateral and offer are created in setup.
    address internal borrower;
    /// @dev Interface to the live cbBTC token.
    IERC20 internal cbBtc = IERC20(CB_BTC);

    /// @dev Pre-settlement values used to prove the settlement deltas.
    struct Snapshot {
        /// @dev LP credit before taking the offer.
        uint256 lpCredit;
        /// @dev LP debt before taking the offer.
        uint256 lpDebt;
        /// @dev Borrower debt before taking the offer.
        uint256 borrowerDebt;
        /// @dev Borrower's USDC balance before taking the offer.
        uint256 borrowerUsdc;
        /// @dev Account gross buyer-asset accounting before taking the offer.
        uint256 committed;
    }

    /// @notice Builds the live account fixture and a collateralized fork borrower.
    /// @dev The account is authorized by the LP, while the borrower authorizes
    ///      the deployed SetterRatifier for the offer created by the test.
    function setUp() public override {
        super.setUp();

        borrower = makeAddr("fork-borrower");
        registry.setRatifierApproval(SETTER_RATIFIER, true);

        vm.prank(LP_OWNER);
        account.setExecutor(address(this), true);

        vm.prank(LP_OWNER);
        midnight.setIsAuthorized(address(account), true, LP_OWNER);

        _fundAndAuthorizeBorrower();
    }

    /// @notice Settles a valid borrower sell offer through the full account path.
    /// @dev The assertions cover collateral supply, ratification, v4 removal,
    ///      Midnight debt/credit changes, borrower proceeds, accounting, and
    ///      callback cleanup.
    function testForkAutoLendSettlesLiveBorrowerOffer() public {
        UnightPolicy memory policy = defaultPolicy();
        policy.reactivationReserve = 0;
        policy.maxContinuousFee = type(uint256).max;
        policy.maxSettlementFee = type(uint256).max;
        policy.expiry = block.timestamp + 2 days;

        vm.prank(LP_OWNER);
        account.setPolicy(policy);

        setPoolTick(BELOW_TERMINAL_TICK);

        uint256 units = 1_000e6;
        uint256 maxBuyerAssets = 2_000e6;
        uint256 deadline = block.timestamp + 1 hours;
        IMidnight.Offer memory offer = _buildOffer(units, deadline);
        bytes memory ratifierData = _ratify(offer);
        Snapshot memory before = Snapshot(
            midnight.credit(MARKET_ID, LP_OWNER),
            midnight.debt(MARKET_ID, LP_OWNER),
            midnight.debt(MARKET_ID, borrower),
            usdc.balanceOf(borrower),
            account.committedBuyerAssets()
        );

        (uint256 buyerAssets, uint256 sellerAssets) =
            account.takeAutoLend(offer, ratifierData, units, maxBuyerAssets, units, deadline);

        assertGt(buyerAssets, 0);
        assertGt(sellerAssets, 0);
        assertGt(midnight.credit(MARKET_ID, LP_OWNER), before.lpCredit);
        assertEq(midnight.debt(MARKET_ID, LP_OWNER), before.lpDebt);
        assertGt(midnight.debt(MARKET_ID, borrower), before.borrowerDebt);
        assertGt(usdc.balanceOf(borrower), before.borrowerUsdc);
        assertEq(account.committedBuyerAssets(), before.committed + buyerAssets);
        assertEq(account.autoLendBuyerAssets(), buyerAssets);
        assertEq(uint8(account.executionContext().state), 0);
        assertEq(usdc.allowance(address(account), MIDNIGHT), 0);
    }

    /// @notice Supplies one cbBTC to the fork-local borrower and authorizes the
    ///         deployed SetterRatifier to act for that borrower.
    /// @dev `deal` changes only fork state; the collateral supply and protocol
    ///      authorization are performed against live Midnight.
    function _fundAndAuthorizeBorrower() internal {
        uint256 collateralAmount = 1e8; // 1 cbBTC, with cbBTC's 8 decimals.
        deal(CB_BTC, borrower, collateralAmount);

        IMidnight.Market memory market = terminalMarket();
        vm.startPrank(borrower);
        cbBtc.approve(MIDNIGHT, collateralAmount);
        midnight.supplyCollateral(market, 0, collateralAmount, borrower);
        midnight.setIsAuthorized(SETTER_RATIFIER, true, borrower);
        vm.stopPrank();
    }

    /// @notice Creates a positive-price, asset-capped borrower sell offer.
    /// @param units Maximum credit units requested by the test.
    /// @param deadline Offer expiry and callback deadline.
    /// @return offer Live-market offer configured for the fork-local borrower.
    function _buildOffer(uint256 units, uint256 deadline) internal view returns (IMidnight.Offer memory offer) {
        offer = IMidnight.Offer({
            market: terminalMarket(),
            buy: false,
            maker: borrower,
            start: block.timestamp,
            expiry: deadline,
            tick: 5_000,
            group: keccak256("unight-auto-lend-fork"),
            callback: address(0),
            callbackData: bytes(""),
            receiverIfMakerIsSeller: borrower,
            ratifier: SETTER_RATIFIER,
            reduceOnly: false,
            maxUnits: 0,
            maxAssets: uint128(units),
            continuousFeeCap: type(uint256).max
        });
    }

    /// @notice Authorizes the exact offer with a one-leaf Merkle root.
    /// @param offer Offer whose deployed HashLib digest is authorized.
    /// @return ratifierData Root, zero leaf index, and empty proof for the leaf.
    function _ratify(IMidnight.Offer memory offer) internal returns (bytes memory ratifierData) {
        bytes32 root = ForkOfferHash.hashOffer(offer);
        vm.prank(borrower);
        ISetterRatifier(SETTER_RATIFIER).setIsRootRatified(borrower, root, true);
        ratifierData = abi.encode(root, uint256(0), new bytes32[](0));
    }
}
