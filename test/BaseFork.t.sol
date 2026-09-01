// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {UnightAccount} from "../src/UnightAccount.sol";
import {UnightAccountFactory} from "../src/UnightAccountFactory.sol";
import {UnightPolicyRegistry} from "../src/UnightPolicyRegistry.sol";
import {IDormancyOracle} from "../src/interfaces/IDormancyOracle.sol";
import {IMidnight} from "../src/interfaces/IMidnight.sol";
import {V4TerminalPositionAdapter} from "../src/libraries/V4TerminalPositionAdapter.sol";
import {UnightPolicy} from "../src/libraries/UnightTypes.sol";

/// @title Unight Base mainnet fork tests
/// @notice Verifies Unight's account, policy, custody, and callback boundaries
///         against the pinned Base fixtures recorded in `params.md`.
/// @dev Each test starts from Base block 50,000,000. The suite deploys only
///      Unight's local registry, factory, account, and test oracle; Uniswap v4
///      and Midnight are exercised at their live fork addresses.
contract BaseForkTest is Test {
    uint256 internal constant FORK_BLOCK = 50_000_000;
    uint256 internal constant POSITION_ID = 2_742_919;
    uint256 internal constant BUYER_ASSETS = 100e6;
    uint256 internal constant MIN_UNITS = 101e6;
    int24 internal constant TARGET_TERMINAL_TICK = -70_891;

    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address internal constant MIDNIGHT = 0xAdedD8ab6dE832766Fedf0FaC4992E5C4D3EA18A;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant LP_OWNER = 0xFEE77A870474B320F8CA3B8711dD76d87c045F24;
    bytes32 internal constant POOL_ID = 0xca7a9a04f4fbb8e4bbacd89b2597ddabdd8dfb4a6c3e6b7793ac8f75a2e5d89b;
    bytes32 internal constant MARKET_ID = 0x549cd072daf99328554f3a6d2d4d6f4a07f1c59369e891e6391946f9cf75f221;

    IERC20 internal usdc = IERC20(USDC);
    IPositionManager internal positionManager = IPositionManager(POSITION_MANAGER);
    IMidnight internal midnight = IMidnight(MIDNIGHT);
    UnightPolicyRegistry internal registry;
    FixedDormancyOracle internal dormancyOracle;
    UnightAccountFactory internal factory;
    UnightAccount internal account;

    /// @notice Creates a fresh Unight account around the live fork position.
    /// @dev The LP owner is impersonated to deploy the account for the owned
    ///      position, transfer the PositionManager NFT into it, and install
    ///      the test policy.
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), FORK_BLOCK);

        registry = new UnightPolicyRegistry(address(this));
        dormancyOracle = new FixedDormancyOracle(true);
        registry.setPoolApproval(POOL_ID, true);
        registry.setMarketApproval(MARKET_ID, true);
        registry.setRatifierApproval(address(this), true);
        registry.setDormancyOracleApproval(address(dormancyOracle), true);

        factory = new UnightAccountFactory(positionManager, IPoolManager(POOL_MANAGER), midnight, registry);
        vm.prank(LP_OWNER);
        factory.createAccount(LP_OWNER, POSITION_ID, USDC, POOL_ID, dormancyOracle, address(this));
        account = UnightAccount(factory.accountOf(LP_OWNER, POSITION_ID));

        vm.prank(LP_OWNER);
        IERC721(POSITION_MANAGER).safeTransferFrom(LP_OWNER, address(account), POSITION_ID);

        vm.prank(LP_OWNER);
        account.setPolicy(_defaultPolicy());
    }

    /// @notice Confirms the chain, live NFT custody, pool identity, loan token,
    ///         and selected Midnight market used by the suite.
    function testForkFixtureUsesBaseAndLivePosition() public view {
        assertEq(block.chainid, 8453);
        assertEq(IERC721(POSITION_MANAGER).ownerOf(POSITION_ID), address(account));
        assertEq(positionManager.getPositionLiquidity(POSITION_ID), 257_740_997);
        assertEq(account.expectedPoolId(), POOL_ID);
        assertEq(account.loanToken(), USDC);
        assertEq(account.marketId(), MARKET_ID);
    }

    /// @notice Confirms that the factory predicts the deployed account address
    ///         and that the account retains its configured protocol addresses.
    function testFactoryPredictsAndCreatesTheCustodyAccount() public view {
        address predicted = factory.predictAccount(LP_OWNER, POSITION_ID, USDC, POOL_ID, dormancyOracle, address(this));

        assertEq(predicted, address(account));
        assertEq(account.owner(), LP_OWNER);
        assertEq(address(account.positionManager()), POSITION_MANAGER);
        assertEq(address(account.midnight()), MIDNIGHT);
    }

    /// @notice Confirms that the account policy references the live Midnight
    ///         market and that the market metadata matches Base and USDC.
    function testPolicyStoresLiveMidnightMarketConfiguration() public view {
        IMidnight.Market memory market = midnight.toMarket(MARKET_ID);

        assertEq(account.marketId(), MARKET_ID);
        assertEq(account.policyNonce(), 1);
        assertEq(market.chainId, block.chainid);
        assertEq(market.midnight, MIDNIGHT);
        assertEq(market.loanToken, USDC);
        assertGt(market.maturity, 1_790_000_000);
    }

    /// @notice Confirms that an in-range position cannot provide terminal
    ///         lending capacity.
    /// @dev At the selected fork block the pool tick is -64,451, which lies
    ///      inside the fixture range [-70,790, -56,920].
    function testRemainingCapacityRejectsAnInRangePosition() public {
        vm.expectRevert(V4TerminalPositionAdapter.PositionNotTerminal.selector);
        account.remainingCapacity();
    }

    /// @notice Confirms that the account cannot return its NFT before closure.
    function testCannotWithdrawPositionBeforeAccountClose() public {
        vm.expectRevert(UnightAccount.InvalidPolicy.selector);
        vm.prank(LP_OWNER);
        account.withdrawPosition();
    }

    /// @notice Confirms that an owner can close the account and then recover
    ///         the controlled PositionManager NFT.
    /// @dev The selected LP has no Midnight credit or debt at the fork block,
    ///      so the post-close withdrawal invariant is satisfied.
    function testCloseThenWithdrawReturnsTheNFTToTheLP() public {
        vm.prank(LP_OWNER);
        account.close();

        assertTrue(account.closed());
        assertEq(account.policyNonce(), 2);

        vm.prank(LP_OWNER);
        account.withdrawPosition();

        assertEq(IERC721(POSITION_MANAGER).ownerOf(POSITION_ID), LP_OWNER);
    }

    /// @notice Confirms that a caller other than the live Midnight address
    ///         cannot invoke the account's buy callback.
    /// @dev The callback payload is otherwise shaped like the registered
    ///      context; the caller check must fail before settlement logic runs.
    function testRejectsAnUnauthorizedCallbackCaller() public {
        IMidnight.Market memory market = midnight.toMarket(MARKET_ID);
        bytes memory callbackData = abi.encode(account.policyNonce(), account.positionEpoch(), MIN_UNITS);

        vm.expectRevert(UnightAccount.CallbackRejected.selector);
        vm.prank(address(0xBEEF));
        account.onBuy(MARKET_ID, market, BUYER_ASSETS, MIN_UNITS, 0, LP_OWNER, callbackData);
    }

    /// @notice Confirms that a valid callback context can remove only the
    ///         requested amount of terminal liquidity from the live position.
    /// @dev The pool's packed slot is changed with a fork-only cheatcode so the
    ///      live position is safely below its lower bound. The test then calls
    ///      {UnightAccount.onBuy} as the live Midnight address; it does not run
    ///      a complete signed {IMidnight.take} settlement.
    function testCallbackRemovesOnlyRequestedTerminalLiquidity() public {
        UnightPolicy memory policy = _defaultPolicy();
        policy.reactivationReserve = 0;
        policy.expiry = block.timestamp + 2 days;
        vm.prank(LP_OWNER);
        account.setPolicy(policy);
        _setPoolTick(TARGET_TERMINAL_TICK);

        IMidnight.Market memory market = midnight.toMarket(MARKET_ID);
        bytes memory callbackData = abi.encode(account.policyNonce(), account.positionEpoch(), MIN_UNITS);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 liquidityBefore = positionManager.getPositionLiquidity(POSITION_ID);
        uint256 balanceBefore = usdc.balanceOf(address(account));

        account.registerBidContext(
            keccak256("fork-offer"), market, address(0xCAFE), uint128(BUYER_ASSETS), deadline, callbackData
        );

        vm.prank(MIDNIGHT);
        bytes32 result = account.onBuy(MARKET_ID, market, BUYER_ASSETS, MIN_UNITS, 0, LP_OWNER, callbackData);

        assertEq(result, keccak256("morpho.midnight.callbackSuccess"));
        assertEq(account.committedBuyerAssets(), BUYER_ASSETS);
        assertEq(account.autoLendBuyerAssets(), 0);
        assertEq(account.bidBoardBuyerAssets(), BUYER_ASSETS);
        assertGe(account.v4PrincipalRemoved(), BUYER_ASSETS);
        assertLt(positionManager.getPositionLiquidity(POSITION_ID), liquidityBefore);
        assertGe(usdc.balanceOf(address(account)), balanceBefore + BUYER_ASSETS);
        assertEq(usdc.allowance(address(account), MIDNIGHT), BUYER_ASSETS);
        assertEq(uint256(account.executionContext().state), 0);
    }

    /// @notice Confirms that an unauthorized caller is rejected by the
    ///         auto-lend entry point before it can reach Midnight.
    /// @dev The empty offer is intentional because {UnightAccount.onlyExecutor}
    ///      must run before offer validation.
    function testAutoLendRequiresAnExecutorBeforeTouchingMidnight() public {
        IMidnight.Offer memory offer;

        vm.expectRevert(UnightAccount.NotExecutor.selector);
        vm.prank(address(0xBEEF));
        account.takeAutoLend(offer, bytes(""), 1, 1, 1, block.timestamp + 1 hours);
    }

    /// @notice Confirms that the account's ERC-721 receiver rejects a token ID
    ///         other than its configured Uniswap v4 position.
    /// @dev The caller is impersonated as PositionManager so this assertion
    ///      isolates the token-identity check rather than the caller check.
    function testRejectsASecondPositionTokenThroughTheReceiver() public {
        vm.expectRevert(UnightAccount.WrongPosition.selector);
        vm.prank(POSITION_MANAGER);
        account.onERC721Received(address(this), LP_OWNER, POSITION_ID + 1, bytes(""));
    }

    /// @notice Returns the bounded policy used by each fork test.
    /// @dev These values are test inputs from params.md and are not production
    ///      risk limits.
    /// @return policy Policy referencing the selected Base Midnight market.
    function _defaultPolicy() internal pure returns (UnightPolicy memory) {
        return UnightPolicy({
            marketId: MARKET_ID,
            globalCap: 1_000_000e6,
            autoLendCap: 600_000e6,
            bidBoardCap: 400_000e6,
            reactivationReserve: 100_000e6,
            minNetRateWad: 0,
            maxContinuousFee: 0,
            maxSettlementFee: 0,
            expiry: 1_790_000_000,
            minimumDwell: 1 days,
            tickBuffer: 100,
            maxLendableBps: 8_000,
            enabled: true
        });
    }

    /// @notice Sets the forked pool's current tick for the terminal-branch test.
    /// @dev Changes only the packed Pool.State slot read by
    ///      `StateLibrary.getSlot0`. This is a fork-test fixture, not a
    ///      production operation, and does not alter the source contracts.
    /// @param tick Tick to write to the forked pool state.
    function _setPoolTick(int24 tick) internal {
        bytes32 poolStateSlot = keccak256(abi.encodePacked(POOL_ID, bytes32(uint256(6))));
        uint256 word = uint256(vm.load(POOL_MANAGER, poolStateSlot));
        word = (word & ~(uint256(type(uint160).max))) | uint256(TickMath.getSqrtPriceAtTick(tick));
        word = (word & ~(uint256(type(uint24).max) << 160)) | (uint256(uint24(int24(tick))) << 160);
        vm.store(POOL_MANAGER, poolStateSlot, bytes32(word));
    }
}

/// @title Fixed dormancy oracle test double
/// @notice Returns a configured dormancy result for every queried position.
/// @dev This contract stands in for a historical dormancy oracle that has not
///      been deployed by Unight. It has no production authorization or storage
///      integration beyond the fixed result supplied at construction.
contract FixedDormancyOracle is IDormancyOracle {
    bool internal dormant;

    /// @notice Sets the result returned by {isDormant}.
    /// @param initialDormant Result returned for every dormancy query.
    constructor(bool initialDormant) {
        dormant = initialDormant;
    }

    /// @inheritdoc IDormancyOracle
    function isDormant(bytes32, int24, int24, uint24, uint32) external view returns (bool) {
        return dormant;
    }
}
