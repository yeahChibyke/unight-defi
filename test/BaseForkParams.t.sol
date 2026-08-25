// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PositionInfo, PositionInfoLibrary} from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

import {IMidnight} from "../src/interfaces/IMidnight.sol";
import {BaseForkHarness} from "./BaseForkHarness.sol";

/// @notice Validates the pinned Base fork, v4 position, and Midnight fixtures.
/// @dev The assertions target the exact block and live addresses recorded in
///      {params.md}; setup then moves the NFT into the test account.
contract BaseForkParamsTest is BaseForkHarness {
    using PoolIdLibrary for PoolKey;
    using PositionInfoLibrary for PositionInfo;

    /// @notice Confirms the chain ID, block number, and block timestamp fixture.
    function testPinnedNetworkAndBlockParameters() public view {
        assertEq(block.chainid, 8453);
        assertEq(block.number, FORK_BLOCK);
        assertEq(block.timestamp, 1_786_789_347);
    }

    /// @notice Confirms the protocol and loan-token addresses used by the account.
    function testPinnedProtocolAndAssetAddresses() public view {
        assertEq(address(account.positionManager()), POSITION_MANAGER);
        assertEq(address(account.poolManager()), POOL_MANAGER);
        assertEq(address(account.midnight()), MIDNIGHT);
        assertEq(account.loanToken(), USDC);
    }

    /// @notice Confirms the fork position's post-setup custody and liquidity.
    function testPinnedPositionOwnershipAndLiquidity() public view {
        // setUp intentionally transfers the fork fixture NFT into the fresh
        // Unight account; LP_OWNER is the documented pre-test fork owner.
        assertEq(positionNft.ownerOf(POSITION_ID), address(account));
        assertEq(positionManager.getPositionLiquidity(POSITION_ID), 257_740_997);
    }

    /// @notice Confirms the live position's pool key, identity, and tick range.
    function testPinnedPositionPoolKeyAndIdentity() public view {
        (PoolKey memory key, PositionInfo info) = positionManager.getPoolAndPositionInfo(POSITION_ID);

        assertEq(Currency.unwrap(key.currency0), USDC);
        assertEq(Currency.unwrap(key.currency1), 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);
        assertEq(key.fee, 8_388_608);
        assertEq(key.tickSpacing, 10);
        assertEq(address(key.hooks), 0xfaD27BC5ef16A0a2aA3049953C25a48E8858b0C0);
        assertEq(PoolId.unwrap(key.toId()), POOL_ID);
        assertEq(info.tickLower(), LOWER_TICK);
        assertEq(info.tickUpper(), UPPER_TICK);
    }

    /// @notice Confirms the selected Midnight market metadata at the fork block.
    function testPinnedMidnightMarketMetadata() public view {
        IMidnight.Market memory market = terminalMarket();

        assertEq(market.chainId, 8453);
        assertEq(market.midnight, MIDNIGHT);
        assertEq(market.loanToken, USDC);
        assertEq(market.maturity, 1_790_348_400);
        assertEq(market.rcfThreshold, 3_000_000_000);
        assertEq(market.enterGate, address(0));
        assertEq(market.liquidatorGate, address(0));
        assertEq(market.collateralParams.length, 1);
        assertEq(market.collateralParams[0].token, 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf);
        assertEq(market.collateralParams[0].lltv, 860_000_000_000_000_000);
        assertEq(market.collateralParams[0].liquidationCursor, 300_000_000_000_000_000);
        assertEq(market.collateralParams[0].oracle, 0x663BECd10daE6C4A3Dcd89F1d76c1174199639B9);
    }
}
