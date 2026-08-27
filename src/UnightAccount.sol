// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IDormancyOracle} from "./interfaces/IDormancyOracle.sol";
import {IMidnight} from "./interfaces/IMidnight.sol";
import {IMidnightBuyCallback} from "./interfaces/IMidnightBuyCallback.sol";
import {IUnightAccount} from "./interfaces/IUnightAccount.sol";
import {IUnightPolicyRegistry} from "./interfaces/IUnightPolicyRegistry.sol";
import {MarketId} from "./libraries/MarketId.sol";
import {UnightPolicy} from "./libraries/UnightTypes.sol";
import {V4TerminalPositionAdapter} from "./libraries/V4TerminalPositionAdapter.sol";

/// @title Unight LP Account
/// @notice Non-upgradeable account that couples one LP's Uniswap v4 position to
///         one controlled Midnight lending policy.
/// @dev The account owns exactly one v4 position NFT. It removes liquidity only
///      after the position adapter proves terminality and dormancy, and it
///      accepts Midnight callbacks only for a context created in the same flow.
contract UnightAccount is IERC721Receiver, IMidnightBuyCallback, IUnightAccount {
    uint256 private constant BPS = 10_000;
    uint256 private constant WAD = 1e18;
    uint256 private constant YEAR = 365 days;
    bytes32 private constant CALLBACK_SUCCESS = keccak256("morpho.midnight.callbackSuccess");

    /// @notice Callback execution currently being authorized by the account.
    enum ExecutionState {
        Idle,
        AutoLend,
        MakerBid
    }

    /// @notice Data bound to a single Midnight callback.
    /// @dev The context prevents a callback from being reused with another
    ///      offer, policy version, position state, market, or asset cap.
    struct ExecutionContext {
        ExecutionState state;
        bytes32 offerHash;
        bytes32 marketHash;
        bytes32 marketId;
        address expectedBuyer;
        address expectedTaker;
        uint256 maxBuyerAssets;
        uint256 minUnits;
        uint256 preCredit;
        uint256 preDebt;
        uint256 policyNonce;
        uint256 positionEpoch;
        uint256 deadline;
        bytes32 callbackDataHash;
    }

    /// @notice LP that owns the lending position and receives the credit.
    address public immutable override owner;
    /// @notice Uniswap v4 position NFT controlled by this account.
    uint256 public immutable positionId;
    /// @notice Canonical Uniswap v4 PositionManager.
    IPositionManager public immutable positionManager;
    /// @notice PoolManager used to read the position's current tick.
    IPoolManager public immutable poolManager;
    /// @notice Canonical Midnight lending protocol.
    IMidnight public immutable midnight;
    /// @notice Loan token that must be the position's terminal currency.
    address public immutable loanToken;
    /// @notice Pool identity accepted for the controlled position.
    bytes32 public immutable expectedPoolId;
    /// @notice Historical oracle required to prove terminal-position dwell.
    IDormancyOracle public immutable dormancyOracle;
    /// @notice Governance allowlist consulted during account setup and execution.
    IUnightPolicyRegistry public immutable registry;
    /// @notice Ratifier authorized to register maker-bid callback contexts.
    address public immutable bidRatifier;

    /// @notice Current lending and liquidity policy.
    UnightPolicy public policy;
    /// @notice Increments whenever the policy changes and invalidates old contexts.
    uint256 public policyNonce;
    /// @notice Increments when the controlled position lifecycle changes.
    uint256 public positionEpoch;
    /// @notice Cumulative gross buyer assets committed in v1 accounting.
    uint256 public committedBuyerAssets;
    /// @notice Portion of committed assets originated through auto-lending.
    uint256 public autoLendBuyerAssets;
    /// @notice Portion of committed assets originated through maker bids.
    uint256 public bidBoardBuyerAssets;
    /// @notice Principal notionally removed from the v4 position.
    uint256 public v4PrincipalRemoved;
    /// @notice Whether the account has been permanently closed.
    bool public closed;

    /// @notice Addresses allowed to submit auto-lend executions.
    mapping(address executor => bool enabled) public isExecutor;
    /// @dev Cleared after every successful callback or reverted transaction.
    ExecutionContext private _execution;

    error NotOwner();
    error NotExecutor();
    error InvalidState();
    error InvalidPolicy();
    error MarketNotApproved();
    error PoolNotApproved();
    error OracleNotApproved();
    error RatifierNotApproved();
    error AuthorizationMissing();
    error OfferRejected();
    error CallbackRejected();
    error CreditInvariant();
    error DebtInvariant();
    error CapacityExceeded();
    error PositionStillActive();
    error NotPositionManager();
    error WrongPosition();
    error TransferFailed();

    event PolicySet(bytes32 indexed marketId, uint256 indexed policyNonce);
    event ExecutorSet(address indexed executor, bool enabled);
    event AutoLendExecuted(bytes32 indexed offerHash, uint256 buyerAssets, uint256 units);
    event MakerBidExecuted(bytes32 indexed offerHash, uint256 buyerAssets, uint256 units);
    event PositionClosed();
    event PositionWithdrawn(address indexed owner, uint256 indexed positionId);

    /// @param owner_ LP that will own the account's Midnight position.
    /// @param positionId_ Uniswap v4 position NFT assigned to the account.
    /// @param positionManager_ Canonical Uniswap v4 PositionManager.
    /// @param poolManager_ Canonical Uniswap v4 PoolManager.
    /// @param midnight_ Canonical Midnight lending protocol.
    /// @param loanToken_ Token to fund Midnight settlements.
    /// @param expectedPoolId_ Pool identity accepted for the position.
    /// @param dormancyOracle_ Historical oracle used to prove terminality.
    /// @param registry_ Registry that must approve the pool and oracle.
    /// @param bidRatifier_ Ratifier allowed to register maker-bid contexts; may
    ///        be zero when the bid-board mode is disabled.
    constructor(
        address owner_,
        uint256 positionId_,
        IPositionManager positionManager_,
        IPoolManager poolManager_,
        IMidnight midnight_,
        address loanToken_,
        bytes32 expectedPoolId_,
        IDormancyOracle dormancyOracle_,
        IUnightPolicyRegistry registry_,
        address bidRatifier_
    ) {
        if (
            owner_ == address(0) || address(positionManager_) == address(0) || address(poolManager_) == address(0)
                || address(midnight_) == address(0) || loanToken_ == address(0)
                || address(dormancyOracle_) == address(0) || address(registry_) == address(0)
        ) revert InvalidPolicy();
        if (!registry_.isPoolApproved(expectedPoolId_)) revert PoolNotApproved();
        if (!registry_.isDormancyOracleApproved(address(dormancyOracle_))) {
            revert OracleNotApproved();
        }

        owner = owner_;
        positionId = positionId_;
        positionManager = positionManager_;
        poolManager = poolManager_;
        midnight = midnight_;
        loanToken = loanToken_;
        expectedPoolId = expectedPoolId_;
        dormancyOracle = dormancyOracle_;
        registry = registry_;
        bidRatifier = bidRatifier_;
    }

    /// @dev Restricts administrative account changes to the LP owner.
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @dev Allows the LP or an LP-approved keeper to submit auto-lend offers.
    modifier onlyExecutor() {
        if (msg.sender != owner && !isExecutor[msg.sender]) revert NotExecutor();
        _;
    }

    /// @dev Prevents policy and lifecycle changes during a settlement callback.
    modifier idle() {
        if (_execution.state != ExecutionState.Idle) revert InvalidState();
        _;
    }

    /// @notice Returns the market currently selected by the account policy.
    function marketId() external view override returns (bytes32) {
        return policy.marketId;
    }

    /// @notice Returns the active callback context, or an empty context when idle.
    function executionContext() external view returns (ExecutionContext memory) {
        return _execution;
    }

    /// @notice Enables or disables an address as an auto-lend transaction submitter.
    /// @param executor Address whose keeper permission is being changed.
    /// @param enabled Whether the address may call {takeAutoLend}.
    function setExecutor(address executor, bool enabled) external onlyOwner {
        if (executor == address(0)) revert InvalidPolicy();
        isExecutor[executor] = enabled;
        emit ExecutorSet(executor, enabled);
    }

    /// @notice Installs a validated lending, fee, capacity, and dormancy policy.
    /// @dev The market, loan token, chain, maturity, registry approvals, and
    ///      bid-ratifier requirement are checked before the policy is stored.
    /// @param newPolicy Policy to apply to future executions.
    function setPolicy(UnightPolicy calldata newPolicy) external onlyOwner idle {
        if (!newPolicy.enabled || newPolicy.marketId == bytes32(0)) revert InvalidPolicy();
        if (newPolicy.globalCap == 0 || newPolicy.autoLendCap > newPolicy.globalCap) {
            revert InvalidPolicy();
        }
        if (newPolicy.bidBoardCap > newPolicy.globalCap) revert InvalidPolicy();
        if (newPolicy.maxLendableBps == 0 || newPolicy.maxLendableBps > BPS) {
            revert InvalidPolicy();
        }
        if (newPolicy.tickBuffer > 887_272 || newPolicy.expiry <= block.timestamp) {
            revert InvalidPolicy();
        }
        if (newPolicy.bidBoardCap > 0 && bidRatifier == address(0)) revert InvalidPolicy();
        if (!registry.isMarketApproved(newPolicy.marketId)) revert MarketNotApproved();

        IMidnight.Market memory market = midnight.toMarket(newPolicy.marketId);
        if (
            market.chainId != block.chainid || market.midnight != address(midnight) || market.loanToken != loanToken
                || market.maturity <= block.timestamp || newPolicy.expiry >= market.maturity
        ) revert InvalidPolicy();

        policy = newPolicy;
        unchecked {
            ++policyNonce;
        }
        emit PolicySet(newPolicy.marketId, policyNonce);
    }

    /// @notice Stops new executions while preserving the account and its history.
    function disablePolicy() external onlyOwner idle {
        policy.enabled = false;
        unchecked {
            ++policyNonce;
        }
        emit PolicySet(policy.marketId, policyNonce);
    }

    /// @notice Permanently closes the account and revokes its Midnight authorization.
    /// @dev Closing does not withdraw the v4 position while the LP still has an
    ///      outstanding Midnight credit or debt position.
    function close() external onlyOwner idle {
        closed = true;
        policy.enabled = false;
        unchecked {
            ++policyNonce;
            ++positionEpoch;
        }
        if (midnight.isAuthorized(owner, address(this))) {
            midnight.setIsAuthorized(address(this), false, owner);
        }
        emit PositionClosed();
    }

    /// @notice Returns the controlled v4 position NFT to the LP after settlement.
    /// @dev The account must be closed and the LP's selected-market credit and
    ///      debt must both be zero.
    function withdrawPosition() external onlyOwner idle {
        if (!closed) revert InvalidPolicy();
        if (midnight.credit(policy.marketId, owner) != 0 || midnight.debt(policy.marketId, owner) != 0) {
            revert PositionStillActive();
        }
        unchecked {
            ++positionEpoch;
        }
        IERC721(address(positionManager)).safeTransferFrom(address(this), owner, positionId);
        emit PositionWithdrawn(owner, positionId);
    }

    /// @notice Returns remaining auto-lend capacity under live position and policy limits.
    /// @dev Capacity is bounded by terminal principal after reserve, lendable BPS,
    ///      global cap, and the auto-lend cap. Committed capacity is monotonic in v1.
    function remainingCapacity() public view returns (uint256) {
        if (!policy.enabled || closed) return 0;
        uint256 terminalPrincipal = V4TerminalPositionAdapter.snapshot(_adapterConfig()).terminalPrincipal;

        uint256 reserveAdjusted =
            terminalPrincipal > policy.reactivationReserve ? terminalPrincipal - policy.reactivationReserve : 0;
        uint256 lendable = FullMath.mulDiv(terminalPrincipal, policy.maxLendableBps, BPS);
        uint256 liveCapacity = reserveAdjusted < lendable ? reserveAdjusted : lendable;
        uint256 committedRemaining = liveCapacity > committedBuyerAssets ? liveCapacity - committedBuyerAssets : 0;
        uint256 globalRemaining = policy.globalCap > committedBuyerAssets ? policy.globalCap - committedBuyerAssets : 0;
        uint256 modeRemaining = policy.autoLendCap > autoLendBuyerAssets ? policy.autoLendCap - autoLendBuyerAssets : 0;
        uint256 result = committedRemaining < globalRemaining ? committedRemaining : globalRemaining;
        return result < modeRemaining ? result : modeRemaining;
    }

    /// @notice Returns remaining maker-bid capacity under global and bid caps.
    function remainingBidCapacity() public view returns (uint256) {
        if (!policy.enabled || closed) return 0;
        uint256 globalRemaining = policy.globalCap > committedBuyerAssets ? policy.globalCap - committedBuyerAssets : 0;
        uint256 modeRemaining = policy.bidBoardCap > bidBoardBuyerAssets ? policy.bidBoardCap - bidBoardBuyerAssets : 0;
        return globalRemaining < modeRemaining ? globalRemaining : modeRemaining;
    }

    /// @notice Takes a borrower sell offer using the LP as Midnight taker.
    /// @dev The offer must have no maker callback. The account creates a context
    ///      before calling Midnight, funds the callback from terminal v4 liquidity,
    ///      and approves only the exact gross buyer assets returned by Midnight.
    /// @param offer Midnight sell offer to take.
    /// @param ratifierData Data consumed by the offer's approved ratifier.
    /// @param units Credit units requested from the offer.
    /// @param maxBuyerAssets Maximum gross loan-token assets the account accepts.
    /// @param minUnits Minimum units the callback must report.
    /// @param deadline Deadline for the v4 liquidity mutation and callback.
    /// @return buyerAssets Gross assets required by Midnight from the account.
    /// @return sellerAssets Assets reported to the offer maker by Midnight.
    function takeAutoLend(
        IMidnight.Offer calldata offer,
        bytes calldata ratifierData,
        uint256 units,
        uint256 maxBuyerAssets,
        uint256 minUnits,
        uint256 deadline
    ) external onlyExecutor idle returns (uint256 buyerAssets, uint256 sellerAssets) {
        if (!policy.enabled || closed || block.timestamp > policy.expiry) revert OfferRejected();
        if (
            units == 0 || maxBuyerAssets == 0 || minUnits > units || deadline < block.timestamp
                || deadline > offer.expiry
        ) revert OfferRejected();
        if (offer.buy || offer.maker == address(0)) revert OfferRejected();
        if (offer.callback != address(0) || offer.callbackData.length != 0) revert OfferRejected();
        if (!registry.isRatifierApproved(offer.ratifier)) revert RatifierNotApproved();
        if (!_marketMatchesPolicy(offer.market)) revert OfferRejected();
        if (offer.expiry > policy.expiry || offer.expiry > offer.market.maturity) revert OfferRejected();
        if (midnight.credit(policy.marketId, offer.maker) != 0) revert OfferRejected();
        if (midnight.debt(policy.marketId, owner) != 0) revert DebtInvariant();
        if (maxBuyerAssets > remainingCapacity()) revert CapacityExceeded();
        if (!midnight.isAuthorized(owner, address(this))) revert AuthorizationMissing();

        uint256 preCredit = midnight.credit(policy.marketId, owner);
        uint256 preDebt = midnight.debt(policy.marketId, owner);
        bytes32 offerHash = keccak256(abi.encode(offer));
        bytes memory callbackData = abi.encode(offerHash, policyNonce, positionEpoch, maxBuyerAssets, minUnits);
        _execution = ExecutionContext({
            state: ExecutionState.AutoLend,
            offerHash: offerHash,
            marketHash: MarketId.hash(offer.market),
            marketId: policy.marketId,
            expectedBuyer: owner,
            expectedTaker: address(this),
            maxBuyerAssets: maxBuyerAssets,
            minUnits: minUnits,
            preCredit: preCredit,
            preDebt: preDebt,
            policyNonce: policyNonce,
            positionEpoch: positionEpoch,
            deadline: deadline,
            callbackDataHash: keccak256(callbackData)
        });

        (buyerAssets, sellerAssets) =
            midnight.take(offer, ratifierData, units, owner, address(0), address(this), callbackData);

        if (_execution.state != ExecutionState.Idle) revert CallbackRejected();
        if (midnight.credit(policy.marketId, owner) <= preCredit) revert CreditInvariant();
        if (midnight.debt(policy.marketId, owner) != preDebt) revert DebtInvariant();
        emit AutoLendExecuted(offerHash, buyerAssets, units);
    }

    /// @notice Registers a maker-bid callback context through the configured ratifier.
    /// @dev Only {bidRatifier} may call this function. The ratifier has already
    ///      checked the offer's maker, callback, ratifier, and base authorization.
    /// @param offerHash Hash of the exact Midnight offer being ratified.
    /// @param market Market embedded in that offer.
    /// @param taker Address taking the LP's maker offer.
    /// @param maxAssets Maximum buyer assets declared by the offer.
    /// @param deadline Offer expiry used as the callback deadline.
    /// @param callbackData Encoded policy nonce, position epoch, and minimum units.
    function registerBidContext(
        bytes32 offerHash,
        IMidnight.Market calldata market,
        address taker,
        uint128 maxAssets,
        uint256 deadline,
        bytes calldata callbackData
    ) external override idle {
        if (msg.sender != bidRatifier || bidRatifier == address(0)) revert CallbackRejected();
        if (!policy.enabled || closed || block.timestamp > policy.expiry) revert OfferRejected();
        if (!_marketMatchesPolicy(market) || maxAssets == 0) revert OfferRejected();
        if (maxAssets > remainingBidCapacity()) revert CapacityExceeded();
        if (midnight.debt(policy.marketId, owner) != 0) revert DebtInvariant();

        (uint256 callbackPolicyNonce, uint256 callbackPositionEpoch, uint256 minUnits) =
            abi.decode(callbackData, (uint256, uint256, uint256));
        if (
            callbackPolicyNonce != policyNonce || callbackPositionEpoch != positionEpoch || minUnits == 0
                || deadline < block.timestamp
        ) revert CallbackRejected();

        _execution = ExecutionContext({
            state: ExecutionState.MakerBid,
            offerHash: offerHash,
            marketHash: MarketId.hash(market),
            marketId: policy.marketId,
            expectedBuyer: owner,
            expectedTaker: taker,
            maxBuyerAssets: maxAssets,
            minUnits: minUnits,
            preCredit: midnight.credit(policy.marketId, owner),
            preDebt: midnight.debt(policy.marketId, owner),
            policyNonce: policyNonce,
            positionEpoch: positionEpoch,
            deadline: deadline,
            callbackDataHash: keccak256(callbackData)
        });
    }

    /// @notice Receives and validates a Midnight buy callback for an active context.
    /// @dev This is the settlement boundary: it checks all context commitments,
    ///      fee/rate limits, removes only required terminal liquidity, updates
    ///      monotonic accounting, and grants Midnight an exact token allowance.
    /// @param id Midnight market identifier supplied by the protocol.
    /// @param market Full market metadata supplied by the protocol.
    /// @param buyerAssets Gross loan-token assets required from the account.
    /// @param units Credit units exchanged in the settlement.
    /// @param pendingFeeIncrease Fee increase created by the settlement.
    /// @param buyer Address receiving the purchased credit.
    /// @param data Callback data originally committed to the active context.
    function onBuy(
        bytes32 id,
        IMidnight.Market memory market,
        uint256 buyerAssets,
        uint256 units,
        uint256 pendingFeeIncrease,
        address buyer,
        bytes memory data
    ) external override returns (bytes32) {
        if (msg.sender != address(midnight)) revert CallbackRejected();
        ExecutionContext memory context = _execution;
        if (context.state == ExecutionState.Idle) {
            if (data.length != 160) revert CallbackRejected();
            (
                uint256 callbackPolicyNonce,
                uint256 callbackPositionEpoch,
                uint256 minUnits,
                uint256 maxAssets,
                uint256 deadline
            ) = abi.decode(data, (uint256, uint256, uint256, uint256, uint256));
            if (
                !policy.enabled || closed || block.timestamp > policy.expiry || id != policy.marketId || maxAssets == 0
                    || maxAssets > remainingBidCapacity() || midnight.debt(id, owner) != 0
                    || callbackPolicyNonce != policyNonce || callbackPositionEpoch != positionEpoch || minUnits == 0
                    || deadline < block.timestamp || deadline > policy.expiry
            ) revert CallbackRejected();
            _openBidContext(id, market, buyer, data, maxAssets, minUnits, deadline);
            context = _execution;
        }
        if (
            id != context.marketId || buyer != context.expectedBuyer || MarketId.hash(market) != context.marketHash
                || keccak256(data) != context.callbackDataHash || context.policyNonce != policyNonce
                || context.positionEpoch != positionEpoch || buyerAssets == 0 || buyerAssets > context.maxBuyerAssets
                || units < context.minUnits
        ) revert CallbackRejected();
        if (market.maturity <= block.timestamp || block.timestamp > context.deadline) revert CallbackRejected();
        if (midnight.debt(id, owner) != context.preDebt) revert DebtInvariant();
        if (midnight.continuousFee(id) > policy.maxContinuousFee) revert CallbackRejected();
        if (midnight.settlementFee(id, market.maturity - block.timestamp) > policy.maxSettlementFee) {
            revert CallbackRejected();
        }
        if (!_meetsMinimumRate(buyerAssets, units, pendingFeeIncrease, market.maturity)) {
            revert CallbackRejected();
        }

        uint256 principalRemoved = _removeForFunding(buyerAssets, context.deadline);

        committedBuyerAssets += buyerAssets;
        v4PrincipalRemoved += principalRemoved;
        if (context.state == ExecutionState.AutoLend) {
            autoLendBuyerAssets += buyerAssets;
            emit AutoLendExecuted(context.offerHash, buyerAssets, units);
        } else {
            bidBoardBuyerAssets += buyerAssets;
            emit MakerBidExecuted(context.offerHash, buyerAssets, units);
        }

        _approveExact(buyerAssets);
        delete _execution;
        return CALLBACK_SUCCESS;
    }

    /// @dev Opens a maker-bid context from callback commitments after Midnight
    /// has authenticated the offer through its static ratifier call.
    function _openBidContext(
        bytes32 id,
        IMidnight.Market memory market,
        address buyer,
        bytes memory data,
        uint256 maxAssets,
        uint256 minUnits,
        uint256 deadline
    ) internal {
        _execution = ExecutionContext({
            state: ExecutionState.MakerBid,
            offerHash: keccak256(abi.encode(id, market, buyer, data)),
            marketHash: MarketId.hash(market),
            marketId: id,
            expectedBuyer: owner,
            expectedTaker: address(0),
            maxBuyerAssets: maxAssets,
            minUnits: minUnits,
            preCredit: midnight.credit(id, owner),
            preDebt: midnight.debt(id, owner),
            policyNonce: policyNonce,
            positionEpoch: positionEpoch,
            deadline: deadline,
            callbackDataHash: keccak256(data)
        });
    }

    /// @notice Sweeps residual loan tokens after the account has fully settled and closed.
    /// @dev This is for surplus balances, including fees returned with a v4 unwind;
    ///      it cannot run while the selected Midnight position remains active.
    /// @param amount Amount to transfer.
    /// @param recipient Destination for the residual tokens.
    function sweepLoanToken(uint256 amount, address recipient) external onlyOwner idle {
        if (!closed || midnight.credit(policy.marketId, owner) != 0 || midnight.debt(policy.marketId, owner) != 0) {
            revert PositionStillActive();
        }
        if (recipient == address(0) || !IERC20(loanToken).transfer(recipient, amount)) revert TransferFailed();
    }

    /// @notice Accepts only this account's configured v4 position NFT.
    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(positionManager)) revert NotPositionManager();
        if (tokenId != positionId) revert WrongPosition();
        return IERC721Receiver.onERC721Received.selector;
    }

    /// @dev Replaces any previous Midnight allowance with exactly `amount`.
    function _approveExact(uint256 amount) internal {
        IERC20 token = IERC20(loanToken);
        if (token.allowance(address(this), address(midnight)) != 0 && !token.approve(address(midnight), 0)) {
            revert TransferFailed();
        }
        if (!token.approve(address(midnight), amount)) revert TransferFailed();
    }

    /// @dev Delegates the constrained v4 unwind to the internal adapter library.
    function _removeForFunding(uint256 amount, uint256 deadline) internal returns (uint256) {
        return V4TerminalPositionAdapter.removeForFunding(_adapterConfig(), amount, deadline);
    }

    /// @dev Builds adapter configuration from immutable dependencies and policy limits.
    function _adapterConfig() internal view returns (V4TerminalPositionAdapter.Config memory config) {
        config = V4TerminalPositionAdapter.Config({
            positionManager: positionManager,
            poolManager: poolManager,
            dormancyOracle: dormancyOracle,
            positionId: positionId,
            expectedPoolId: expectedPoolId,
            loanToken: loanToken,
            tickBuffer: policy.tickBuffer,
            minimumDwell: policy.minimumDwell
        });
    }

    /// @dev Compares supplied market metadata with Midnight's canonical policy market.
    function _marketMatchesPolicy(IMidnight.Market memory market) internal view returns (bool) {
        if (market.loanToken != loanToken) return false;
        IMidnight.Market memory configuredMarket = midnight.toMarket(policy.marketId);
        return keccak256(abi.encode(market)) == keccak256(abi.encode(configuredMarket));
    }

    /// @dev Applies the configured annualized net-return floor to a settlement.
    function _meetsMinimumRate(uint256 buyerAssets, uint256 units, uint256 pendingFeeIncrease, uint256 maturity)
        internal
        view
        returns (bool)
    {
        if (policy.minNetRateWad == 0) return true;
        if (units <= pendingFeeIncrease || maturity <= block.timestamp) return false;
        uint256 netReturn = units - pendingFeeIncrease;
        if (netReturn <= buyerAssets) return false;
        uint256 gain = netReturn - buyerAssets;
        return FullMath.mulDiv(gain, YEAR * WAD, buyerAssets * (maturity - block.timestamp)) >= policy.minNetRateWad;
    }
}
