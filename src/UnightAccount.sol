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

/// @notice Non-upgradeable per-LP account. The account owns exactly one v4
///         position NFT and is the only address allowed to execute its policy.
contract UnightAccount is IERC721Receiver, IMidnightBuyCallback, IUnightAccount {
    uint256 private constant BPS = 10_000;
    uint256 private constant WAD = 1e18;
    uint256 private constant YEAR = 365 days;
    bytes32 private constant CALLBACK_SUCCESS = keccak256("morpho.midnight.callbackSuccess");

    enum ExecutionState {
        Idle,
        AutoLend,
        MakerBid
    }

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

    address public immutable override owner;
    uint256 public immutable positionId;
    IPositionManager public immutable positionManager;
    IPoolManager public immutable poolManager;
    IMidnight public immutable midnight;
    address public immutable loanToken;
    bytes32 public immutable expectedPoolId;
    IDormancyOracle public immutable dormancyOracle;
    IUnightPolicyRegistry public immutable registry;
    address public immutable bidRatifier;

    UnightPolicy public policy;
    uint256 public policyNonce;
    uint256 public positionEpoch;
    uint256 public committedBuyerAssets;
    uint256 public autoLendBuyerAssets;
    uint256 public bidBoardBuyerAssets;
    uint256 public v4PrincipalRemoved;
    bool public closed;

    mapping(address executor => bool enabled) public isExecutor;
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

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyExecutor() {
        if (msg.sender != owner && !isExecutor[msg.sender]) revert NotExecutor();
        _;
    }

    modifier idle() {
        if (_execution.state != ExecutionState.Idle) revert InvalidState();
        _;
    }

    function marketId() external view override returns (bytes32) {
        return policy.marketId;
    }

    function executionContext() external view returns (ExecutionContext memory) {
        return _execution;
    }

    function setExecutor(address executor, bool enabled) external onlyOwner {
        if (executor == address(0)) revert InvalidPolicy();
        isExecutor[executor] = enabled;
        emit ExecutorSet(executor, enabled);
    }

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

    function disablePolicy() external onlyOwner idle {
        policy.enabled = false;
        unchecked {
            ++policyNonce;
        }
        emit PolicySet(policy.marketId, policyNonce);
    }

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

    function remainingBidCapacity() public view returns (uint256) {
        if (!policy.enabled || closed) return 0;
        uint256 globalRemaining = policy.globalCap > committedBuyerAssets ? policy.globalCap - committedBuyerAssets : 0;
        uint256 modeRemaining = policy.bidBoardCap > bidBoardBuyerAssets ? policy.bidBoardCap - bidBoardBuyerAssets : 0;
        return globalRemaining < modeRemaining ? globalRemaining : modeRemaining;
    }

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
        if (context.state == ExecutionState.Idle) revert CallbackRejected();
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

    function sweepLoanToken(uint256 amount, address recipient) external onlyOwner idle {
        if (!closed || midnight.credit(policy.marketId, owner) != 0 || midnight.debt(policy.marketId, owner) != 0) {
            revert PositionStillActive();
        }
        if (recipient == address(0) || !IERC20(loanToken).transfer(recipient, amount)) revert TransferFailed();
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external view returns (bytes4) {
        if (msg.sender != address(positionManager)) revert NotPositionManager();
        if (tokenId != positionId) revert WrongPosition();
        return IERC721Receiver.onERC721Received.selector;
    }

    function _approveExact(uint256 amount) internal {
        IERC20 token = IERC20(loanToken);
        if (token.allowance(address(this), address(midnight)) != 0 && !token.approve(address(midnight), 0)) {
            revert TransferFailed();
        }
        if (!token.approve(address(midnight), amount)) revert TransferFailed();
    }

    function _removeForFunding(uint256 amount, uint256 deadline) internal returns (uint256) {
        return V4TerminalPositionAdapter.removeForFunding(_adapterConfig(), amount, deadline);
    }

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

    function _marketMatchesPolicy(IMidnight.Market memory market) internal view returns (bool) {
        if (market.loanToken != loanToken) return false;
        IMidnight.Market memory configuredMarket = midnight.toMarket(policy.marketId);
        return keccak256(abi.encode(market)) == keccak256(abi.encode(configuredMarket));
    }

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
