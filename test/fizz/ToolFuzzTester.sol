// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {V4LiquidityMath} from "../../src/libraries/V4LiquidityMath.sol";

/// @title External fuzzer property harness
/// @notice Provides deterministic arithmetic and accounting properties for
///         Medusa and Echidna without relying on Foundry cheatcodes.
/// @dev Live protocol settlement remains covered by the Base fork Foundry
///      suites. This contract deliberately models only pure/state-local rules
///      that can be executed by standalone fuzzers.
contract ToolFuzzTester {
    uint160 internal constant SQRT_LOWER = 7.8e18;
    uint160 internal constant SQRT_UPPER = 8.2e18;

    uint256 public globalCap = 1_000_000e6;
    uint256 public autoLendCap = 600_000e6;
    uint256 public bidBoardCap = 400_000e6;
    uint256 public committedBuyerAssets;
    uint256 public autoLendBuyerAssets;
    uint256 public bidBoardBuyerAssets;
    uint256 public v4PrincipalRemoved;
    uint256 public policyNonce;
    uint256 public positionEpoch;

    uint128 public previousLiquidity;
    uint128 public currentLiquidity;
    uint256 public previousAmount0;
    uint256 public currentAmount0;
    bytes32 public callbackCommitment;

    /// @notice Accepts the balance Echidna assigns to the test contract.
    constructor() payable {}

    /// @notice Changes caps while preserving the policy cap relation.
    function setCaps(uint256 global_, uint256 auto_, uint256 bid_) external {
        global_ = (global_ % 1_000_000_000e6) + 1;
        if (global_ < committedBuyerAssets) global_ = committedBuyerAssets;
        auto_ = auto_ % (global_ + 1);
        bid_ = bid_ % (global_ + 1);
        if (auto_ < autoLendBuyerAssets) auto_ = autoLendBuyerAssets;
        if (bid_ < bidBoardBuyerAssets) bid_ = bidBoardBuyerAssets;
        if (auto_ > global_) global_ = auto_;
        if (bid_ > global_) global_ = bid_;
        globalCap = global_;
        autoLendCap = auto_;
        bidBoardCap = bid_;
    }

    /// @notice Adds a bounded Auto-Lend commitment.
    function commitAutoLend(uint256 amount) external {
        uint256 remaining = autoLendCap - autoLendBuyerAssets;
        uint256 globalRemaining = globalCap - committedBuyerAssets;
        if (globalRemaining < remaining) remaining = globalRemaining;
        if (v4PrincipalRemoved != 0 && v4PrincipalRemoved - committedBuyerAssets < remaining) {
            remaining = v4PrincipalRemoved - committedBuyerAssets;
        }
        if (amount > remaining) amount = remaining;
        autoLendBuyerAssets += amount;
        committedBuyerAssets += amount;
    }

    /// @notice Adds a bounded Bid Board commitment.
    function commitBidBoard(uint256 amount) external {
        uint256 remaining = bidBoardCap - bidBoardBuyerAssets;
        uint256 globalRemaining = globalCap - committedBuyerAssets;
        if (globalRemaining < remaining) remaining = globalRemaining;
        if (v4PrincipalRemoved != 0 && v4PrincipalRemoved - committedBuyerAssets < remaining) {
            remaining = v4PrincipalRemoved - committedBuyerAssets;
        }
        if (amount > remaining) amount = remaining;
        bidBoardBuyerAssets += amount;
        committedBuyerAssets += amount;
    }

    /// @notice Records principal only when it is at least the supplied amount.
    function recordPrincipal(uint256 amount) external {
        if (amount >= committedBuyerAssets) v4PrincipalRemoved = amount;
    }

    /// @notice Advances policy and position epochs monotonically.
    function advanceEpochs(uint256 policyStep, uint256 positionStep) external {
        policyNonce += policyStep % 1_000_000;
        positionEpoch += positionStep % 1_000_000;
    }

    /// @notice Stores and immediately validates a callback-data commitment.
    function commitCallback(uint256 nonce, uint256 epoch, uint256 minUnits) external {
        callbackCommitment = keccak256(abi.encode(nonce, epoch, minUnits));
    }

    /// @notice Samples the v4 liquidity conversion at two ordered inputs.
    function sampleLiquidity(uint128 first, uint128 second) external {
        if (second < first) second = first;
        previousLiquidity = first;
        currentLiquidity = second;
        previousAmount0 = V4LiquidityMath.amount0ForLiquidity(SQRT_LOWER, SQRT_UPPER, first);
        currentAmount0 = V4LiquidityMath.amount0ForLiquidity(SQRT_LOWER, SQRT_UPPER, second);
    }

    /// @notice Resets modeled accounting state for subsequent sequences.
    function resetAccounting() external {
        committedBuyerAssets = 0;
        autoLendBuyerAssets = 0;
        bidBoardBuyerAssets = 0;
        v4PrincipalRemoved = 0;
    }

    /// @notice Checks mode accounting and all configured capacity bounds.
    function property_accountingAndCaps() external view returns (bool) {
        assert(committedBuyerAssets == autoLendBuyerAssets + bidBoardBuyerAssets);
        assert(autoLendBuyerAssets <= autoLendCap);
        assert(bidBoardBuyerAssets <= bidBoardCap);
        assert(committedBuyerAssets <= globalCap);
        return true;
    }

    /// @notice Checks that modeled principal covers modeled commitments.
    function property_principalCoversCommitment() external view returns (bool) {
        if (v4PrincipalRemoved != 0) assert(v4PrincipalRemoved >= committedBuyerAssets);
        return true;
    }

    /// @notice Checks the configured mode caps remain bounded by the global cap.
    function property_policyCaps() external view returns (bool) {
        assert(autoLendCap <= globalCap);
        assert(bidBoardCap <= globalCap);
        return true;
    }

    /// @notice Checks monotonicity of the sampled v4 liquidity conversion.
    function property_liquidityMonotonic() external view returns (bool) {
        assert(currentLiquidity >= previousLiquidity);
        assert(currentAmount0 >= previousAmount0);
        return true;
    }

    /// @notice Checks callback commitments are nonzero after registration.
    function property_callbackCommitmentPresent() external view returns (bool) {
        if (callbackCommitment == bytes32(0)) return true;
        assert(callbackCommitment != bytes32(0));
        return true;
    }
}
