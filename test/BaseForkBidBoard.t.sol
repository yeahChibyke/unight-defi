// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IMidnightRatifier} from "../src/interfaces/IMidnightRatifier.sol";
import {ISetterRatifier} from "../src/interfaces/ISetterRatifier.sol";
import {IMidnight} from "../src/interfaces/IMidnight.sol";
import {UnightAccount} from "../src/UnightAccount.sol";
import {UnightPolicy} from "../src/libraries/UnightTypes.sol";
import {V4TerminalPositionAdapter} from "../src/libraries/V4TerminalPositionAdapter.sol";
import {BaseForkHarness} from "./BaseForkHarness.sol";
import {ForkOfferHash} from "./ForkOfferHash.sol";

/// @title Base fork LP Bid Board settlement tests
/// @notice Exercises live Midnight buy offers whose maker callback is the
///         fork-local Unight account.
/// @dev The test contract is the account's configured bid-ratifier boundary and
///      delegates static offer authorization to the deployed SetterRatifier.
///      Midnight, USDC, cbBTC, the oracle, and Uniswap v4 remain live fork state.
contract BaseForkBidBoardTest is BaseForkHarness, IMidnightRatifier {
    /// @dev Deployed Base SetterRatifier used for the offer's authorization root.
    address internal constant SETTER_RATIFIER = 0x800B5F12A61B8198a5a6EfD794Cac6699B294d63;
    /// @dev Deployed Base cbBTC collateral token.
    address internal constant CB_BTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
    /// @dev One cbp, the smallest valid Midnight settlement-fee unit.
    uint256 internal constant ONE_CBP = 1e12;
    /// @dev Nonzero continuous fee used only in the fork fee scenario.
    uint256 internal constant CONTINUOUS_FEE = 1e6;

    address internal borrower;
    IERC20 internal cbBtc = IERC20(CB_BTC);

    /// @notice Creates collateral, authorizations, and a terminal LP position.
    function setUp() public override {
        super.setUp();
        borrower = makeAddr("bid-borrower");
        registry.setRatifierApproval(address(this), true);

        vm.prank(LP_OWNER);
        account.setExecutor(address(this), true);
        vm.prank(LP_OWNER);
        midnight.setIsAuthorized(address(this), true, LP_OWNER);

        deal(CB_BTC, borrower, 1e8);
        IMidnight.Market memory market = terminalMarket();
        vm.startPrank(borrower);
        cbBtc.approve(MIDNIGHT, 1e8);
        midnight.supplyCollateral(market, 0, 1e8, borrower);
        midnight.setIsAuthorized(address(this), true, borrower);
        vm.stopPrank();

        _configureTestPolicy();
        setPoolTick(BELOW_TERMINAL_TICK);
    }

    /// @notice Settles an LP bid end-to-end through live Midnight and v4.
    /// @dev The borrower is the live Midnight taker; the LP remains the credit
    ///      buyer and receives the resulting live Midnight credit position.
    function testLiveLpBidBoardSettlement() public {
        uint256 units = 1_000e6;
        IMidnight.Offer memory offer = _buildOffer(units, block.timestamp + 1 hours, keccak256("bid-happy"));
        bytes memory ratifierData = _authorizeOffer(offer, LP_OWNER);
        uint256 lpCreditBefore = midnight.credit(MARKET_ID, LP_OWNER);
        uint256 borrowerDebtBefore = midnight.debt(MARKET_ID, borrower);
        uint256 borrowerUsdcBefore = usdc.balanceOf(borrower);

        (uint256 buyerAssets, uint256 sellerAssets) = _take(offer, ratifierData, units);

        assertGt(buyerAssets, 0);
        assertGt(sellerAssets, 0);
        assertGt(midnight.credit(MARKET_ID, LP_OWNER), lpCreditBefore);
        assertGt(midnight.debt(MARKET_ID, borrower), borrowerDebtBefore);
        assertGt(usdc.balanceOf(borrower), borrowerUsdcBefore);
        assertEq(account.bidBoardBuyerAssets(), buyerAssets);
        assertEq(uint8(account.executionContext().state), 0);
    }

    /// @notice Proves that one asset-capped bid can be filled in separate takes.
    function testPartialFillsConsumeOneOfferGroupIncrementally() public {
        uint256 units = 1_000e6;
        bytes32 group = keccak256("bid-partial");
        IMidnight.Offer memory offer = _buildOffer(3_000e6, block.timestamp + 1 hours, group);
        bytes memory ratifierData = _authorizeOffer(offer, LP_OWNER);

        (uint256 firstBuyerAssets,) = _take(offer, ratifierData, units);
        uint256 consumedAfterFirst = midnight.consumed(LP_OWNER, group);
        (uint256 secondBuyerAssets,) = _take(offer, ratifierData, units);

        assertGt(firstBuyerAssets, 0);
        assertGt(secondBuyerAssets, 0);
        assertEq(midnight.consumed(LP_OWNER, group), consumedAfterFirst + secondBuyerAssets);
        assertEq(account.bidBoardBuyerAssets(), firstBuyerAssets + secondBuyerAssets);
    }

    /// @notice Rejects a cancelled offer group without consuming LP liquidity.
    function testCancelledOfferGroupRevertsAndRollsBack() public {
        IMidnight.Offer memory offer = _buildOffer(1_000e6, block.timestamp + 1 hours, keccak256("bid-cancel"));
        bytes memory ratifierData = _authorizeOffer(offer, LP_OWNER);
        uint256 liquidityBefore = positionManager.getPositionLiquidity(POSITION_ID);

        vm.prank(LP_OWNER);
        midnight.setConsumed(offer.group, type(uint128).max, LP_OWNER);

        vm.expectRevert();
        _take(offer, ratifierData, 1_000e6);
        assertEq(positionManager.getPositionLiquidity(POSITION_ID), liquidityBefore);
        assertEq(account.committedBuyerAssets(), 0);
    }

    /// @notice Confirms cancelling one group does not cancel an independent bid.
    /// @dev Both offers use the live SetterRatifier and the same LP position;
    ///      only the first group's consumed amount is pre-marked.
    function testCancellationIsScopedToItsOfferGroup() public {
        IMidnight.Offer memory cancelled =
            _buildOffer(1_000e6, block.timestamp + 1 hours, keccak256("bid-cancelled-only"));
        IMidnight.Offer memory available =
            _buildOffer(1_000e6, block.timestamp + 1 hours, keccak256("bid-available-group"));
        bytes memory cancelledData = _authorizeOffer(cancelled, LP_OWNER);
        bytes memory availableData = _authorizeOffer(available, LP_OWNER);

        vm.prank(LP_OWNER);
        midnight.setConsumed(cancelled.group, type(uint128).max, LP_OWNER);

        vm.expectRevert();
        _take(cancelled, cancelledData, 1_000e6);
        (uint256 buyerAssets,) = _take(available, availableData, 1_000e6);
        assertGt(buyerAssets, 0);
        assertEq(account.committedBuyerAssets(), buyerAssets);
    }

    /// @notice Verifies nonzero settlement fees widen the buyer/seller asset
    ///         spread and are accepted by the account policy.
    function testNonzeroSettlementFeeIsSettledAndAccounted() public {
        _setNonzeroFees();
        IMidnight.Offer memory offer = _buildOffer(1_000e6, block.timestamp + 1 hours, keccak256("bid-fee"));
        bytes memory ratifierData = _authorizeOffer(offer, LP_OWNER);
        uint256 feeBefore = _claimableSettlementFee();

        (uint256 buyerAssets, uint256 sellerAssets) = _take(offer, ratifierData, 1_000e6);

        assertGt(buyerAssets, sellerAssets);
        assertGt(_claimableSettlementFee(), feeBefore);
        assertEq(account.bidBoardBuyerAssets(), buyerAssets);
    }

    /// @notice Verifies a nonzero continuous fee becomes LP pending fee.
    function testNonzeroContinuousFeeAccruesOnLiveCredit() public {
        _setNonzeroFees();
        IMidnight.Offer memory offer = _buildOffer(1_000e6, block.timestamp + 1 hours, keccak256("bid-continuous"));
        bytes memory ratifierData = _authorizeOffer(offer, LP_OWNER);

        _take(offer, ratifierData, 1_000e6);

        assertGt(midnight.pendingFee(MARKET_ID, LP_OWNER), 0);
    }

    /// @notice Rejects a settlement whose live fee exceeds the account policy.
    /// @dev The live take must revert atomically, including its v4 liquidity,
    ///      Midnight debt/credit, fee accounting, and callback context.
    function testSettlementFeeCapFailureRollsBack() public {
        _setNonzeroFees();
        UnightPolicy memory policy = defaultPolicy();
        policy.reactivationReserve = 0;
        policy.maxContinuousFee = type(uint256).max;
        policy.expiry = block.timestamp + 2 days;
        policy.maxSettlementFee = 0;
        vm.prank(LP_OWNER);
        account.setPolicy(policy);

        IMidnight.Offer memory offer = _buildOffer(1_000e6, block.timestamp + 1 hours, keccak256("bid-fee-cap"));
        bytes memory ratifierData = _authorizeOffer(offer, LP_OWNER);
        uint256 liquidityBefore = positionManager.getPositionLiquidity(POSITION_ID);
        uint256 creditBefore = midnight.credit(MARKET_ID, LP_OWNER);
        uint256 debtBefore = midnight.debt(MARKET_ID, borrower);

        vm.expectRevert();
        _take(offer, ratifierData, 1_000e6);

        assertEq(positionManager.getPositionLiquidity(POSITION_ID), liquidityBefore);
        assertEq(midnight.credit(MARKET_ID, LP_OWNER), creditBefore);
        assertEq(midnight.debt(MARKET_ID, borrower), debtBefore);
        assertEq(account.committedBuyerAssets(), 0);
        assertEq(uint8(account.executionContext().state), 0);
    }

    /// @notice Proves a callback failure leaves v4, Midnight, and Unight state unchanged.
    function testCallbackFailureRollsBackAllSettlementState() public {
        IMidnight.Offer memory offer = _buildOffer(1_000e6, block.timestamp + 1 hours, keccak256("bid-rollback"));
        bytes memory ratifierData = _authorizeOffer(offer, LP_OWNER);
        uint256 liquidityBefore = positionManager.getPositionLiquidity(POSITION_ID);
        uint256 creditBefore = midnight.credit(MARKET_ID, LP_OWNER);
        uint256 consumedBefore = midnight.consumed(LP_OWNER, offer.group);

        setPoolTick(ACTIVE_TICK);
        vm.expectRevert(V4TerminalPositionAdapter.PositionNotTerminal.selector);
        _take(offer, ratifierData, 1_000e6);

        assertEq(positionManager.getPositionLiquidity(POSITION_ID), liquidityBefore);
        assertEq(midnight.credit(MARKET_ID, LP_OWNER), creditBefore);
        assertEq(midnight.consumed(LP_OWNER, offer.group), consumedBefore);
        assertEq(account.committedBuyerAssets(), 0);
        assertEq(uint8(account.executionContext().state), 0);
    }

    /// @notice Proves an undercollateralized borrower cannot complete settlement.
    /// @dev The borrower keeps only 0.01 cbBTC, making the requested debt exceed
    ///      the live oracle-valued LLTV limit; the failed take must roll back.
    function testUnhealthyBorrowerRevertsAndRollsBack() public {
        IMidnight.Market memory market = terminalMarket();
        vm.prank(borrower);
        midnight.withdrawCollateral(market, 0, 99e6, borrower, borrower);
        assertTrue(midnight.isHealthy(market, MARKET_ID, borrower));

        IMidnight.Offer memory offer = _buildOffer(2_000e6, block.timestamp + 1 hours, keccak256("bid-health"));
        bytes memory ratifierData = _authorizeOffer(offer, LP_OWNER);
        uint256 liquidityBefore = positionManager.getPositionLiquidity(POSITION_ID);

        vm.expectRevert();
        _take(offer, ratifierData, 2_000e6);

        assertEq(positionManager.getPositionLiquidity(POSITION_ID), liquidityBefore);
        assertEq(midnight.debt(MARKET_ID, borrower), 0);
        assertEq(account.committedBuyerAssets(), 0);
    }

    /// @notice Rejects a live maker bid at the selected market's maturity.
    function testLiveMidnightRejectsBidAtMarketMaturity() public {
        vm.warp(terminalMarket().maturity);
        IMidnight.Offer memory offer = _buildOffer(1_000e6, block.timestamp + 1 hours, keccak256("bid-maturity"));

        vm.expectRevert();
        _take(offer, bytes(""), 1_000e6);
    }

    /// @notice Rejects a live offer after its own expiry while preserving state.
    function testExpiredBidIsRejectedByLiveMidnight() public {
        uint256 expiry = block.timestamp + 1 hours;
        IMidnight.Offer memory offer = _buildOffer(1_000e6, expiry, keccak256("bid-expired"));
        bytes memory ratifierData = _authorizeOffer(offer, LP_OWNER);
        vm.warp(expiry + 1);

        vm.expectRevert();
        _take(offer, ratifierData, 1_000e6);
        assertEq(account.committedBuyerAssets(), 0);
    }

    /// @notice Implements the configured ratifier boundary used by this fork.
    /// @dev Midnight calls this function during `take`; the deployed
    ///      SetterRatifier validates the authorized root. The account opens its
    ///      maker-bid context when the authenticated callback arrives.
    function isRatified(IMidnight.Offer memory offer, bytes memory ratifierData, address)
        external
        view
        returns (bytes32)
    {
        (bytes32 root, uint256 leafIndex, bytes32[] memory proof) =
            abi.decode(ratifierData, (bytes32, uint256, bytes32[]));
        if (leafIndex != 0 || proof.length != 0 || root != ForkOfferHash.hashOffer(offer)) revert();
        if (!ISetterRatifier(SETTER_RATIFIER).isRootRatified(offer.maker, root)) revert();
        if (
            !offer.buy || offer.maker != LP_OWNER || offer.callback != address(account)
                || offer.ratifier != address(this)
        ) {
            revert();
        }
        return keccak256("morpho.midnight.callbackSuccess");
    }

    function _take(IMidnight.Offer memory offer, bytes memory ratifierData, uint256 units)
        internal
        returns (uint256 buyerAssets, uint256 sellerAssets)
    {
        return midnight.take(offer, ratifierData, units, borrower, borrower, address(0), bytes(""));
    }

    function _buildOffer(uint256 maxAssets, uint256 expiry, bytes32 group)
        internal
        view
        returns (IMidnight.Offer memory offer)
    {
        offer = IMidnight.Offer({
            market: terminalMarket(),
            buy: true,
            maker: LP_OWNER,
            start: block.timestamp,
            expiry: expiry,
            tick: 5_000,
            group: group,
            callback: address(account),
            callbackData: abi.encode(account.policyNonce(), account.positionEpoch(), 1_000e6, maxAssets, expiry),
            receiverIfMakerIsSeller: address(0),
            ratifier: address(this),
            reduceOnly: false,
            maxUnits: 0,
            maxAssets: uint128(maxAssets),
            continuousFeeCap: type(uint256).max
        });
    }

    function _authorizeOffer(IMidnight.Offer memory offer, address maker) internal returns (bytes memory ratifierData) {
        bytes32 root = ForkOfferHash.hashOffer(offer);
        vm.prank(maker);
        ISetterRatifier(SETTER_RATIFIER).setIsRootRatified(maker, root, true);
        ratifierData = abi.encode(root, uint256(0), new bytes32[](0));
    }

    function _configureTestPolicy() internal {
        UnightPolicy memory policy = defaultPolicy();
        policy.reactivationReserve = 0;
        policy.maxContinuousFee = type(uint256).max;
        policy.maxSettlementFee = type(uint256).max;
        policy.expiry = block.timestamp + 2 days;
        vm.prank(LP_OWNER);
        account.setPolicy(policy);
    }

    function _setNonzeroFees() internal {
        address feeSetter = midnight.feeSetter();
        vm.startPrank(feeSetter);
        for (uint256 i; i < 7; ++i) {
            midnight.setMarketSettlementFee(MARKET_ID, i, ONE_CBP);
        }
        midnight.setMarketContinuousFee(MARKET_ID, CONTINUOUS_FEE);
        vm.stopPrank();
    }

    function _claimableSettlementFee() internal view returns (uint256 amount) {
        amount = midnight.claimableSettlementFee(USDC);
    }
}
