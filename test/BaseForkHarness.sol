// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

import {IDormancyOracle} from "../src/interfaces/IDormancyOracle.sol";
import {IMidnight} from "../src/interfaces/IMidnight.sol";
import {UnightAccount} from "../src/UnightAccount.sol";
import {UnightAccountFactory} from "../src/UnightAccountFactory.sol";
import {UnightPolicyRegistry} from "../src/UnightPolicyRegistry.sol";
import {UnightPolicy} from "../src/libraries/UnightTypes.sol";

/// @notice Shared Base mainnet-fork fixture for the focused Unight test files.
/// @dev Every derived test creates a fresh fork at the pinned block and uses
///      live Base v4, USDC, and Midnight contracts. Only the registry,
///      account, factory, and dormancy oracle are fork-local deployments.
abstract contract BaseForkHarness is Test {
    /// @dev Fixed Base block used for deterministic fork state.
    uint256 internal constant FORK_BLOCK = 50_000_000;
    /// @dev Real v4 position used by the fork tests.
    uint256 internal constant POSITION_ID = 2_742_919;
    /// @dev Lower and upper ticks of the real fork position.
    int24 internal constant LOWER_TICK = -70_790;
    int24 internal constant UPPER_TICK = -56_920;
    /// @dev Pool tick recorded at the fork block.
    int24 internal constant ACTIVE_TICK = -64_451;
    /// @dev Fork-local ticks used to exercise the terminal branches.
    int24 internal constant BELOW_TERMINAL_TICK = -70_891;
    int24 internal constant ABOVE_TERMINAL_TICK = -56_819;

    address internal constant POOL_MANAGER = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address internal constant POSITION_MANAGER = 0x7C5f5A4bBd8fD63184577525326123B519429bDc;
    address internal constant MIDNIGHT = 0xAdedD8ab6dE832766Fedf0FaC4992E5C4D3EA18A;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant LP_OWNER = 0xFEE77A870474B320F8CA3B8711dD76d87c045F24;
    bytes32 internal constant POOL_ID = 0xca7a9a04f4fbb8e4bbacd89b2597ddabdd8dfb4a6c3e6b7793ac8f75a2e5d89b;
    bytes32 internal constant MARKET_ID = 0x549cd072daf99328554f3a6d2d4d6f4a07f1c59369e891e6391946f9cf75f221;

    IERC20 internal usdc = IERC20(USDC);
    IERC721 internal positionNft = IERC721(POSITION_MANAGER);
    IPositionManager internal positionManager = IPositionManager(POSITION_MANAGER);
    IPoolManager internal poolManager = IPoolManager(POOL_MANAGER);
    IMidnight internal midnight = IMidnight(MIDNIGHT);
    UnightPolicyRegistry internal registry;
    ForkDormancyOracle internal dormancyOracle;
    UnightAccountFactory internal factory;
    UnightAccount internal account;

    /// @notice Creates the live Base fixture and a fresh Unight account.
    /// @dev The NFT is transferred from the documented LP owner into the
    ///      account, so tests observe post-custody state after setup.
    function setUp() public virtual {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"), FORK_BLOCK);

        registry = new UnightPolicyRegistry(address(this));
        dormancyOracle = new ForkDormancyOracle(true);
        registry.setPoolApproval(POOL_ID, true);
        registry.setMarketApproval(MARKET_ID, true);
        registry.setRatifierApproval(address(this), true);
        registry.setDormancyOracleApproval(address(dormancyOracle), true);

        factory = new UnightAccountFactory(positionManager, poolManager, midnight, registry);
        factory.createAccount(LP_OWNER, POSITION_ID, USDC, POOL_ID, dormancyOracle, address(this));
        account = UnightAccount(factory.accountOf(LP_OWNER, POSITION_ID));

        vm.prank(LP_OWNER);
        positionNft.safeTransferFrom(LP_OWNER, address(account), POSITION_ID);

        vm.prank(LP_OWNER);
        account.setPolicy(defaultPolicy());
    }

    /// @notice Returns the conservative policy shared by the fork tests.
    /// @dev These values are test inputs, not production risk limits.
    function defaultPolicy() internal pure returns (UnightPolicy memory) {
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

    /// @notice Reads the pinned market metadata from the live Midnight contract.
    function terminalMarket() internal view returns (IMidnight.Market memory) {
        return midnight.toMarket(MARKET_ID);
    }

    /// @notice Changes only the forked PoolManager slot0 tick and sqrt price.
    /// @dev This is a test-only state mutation used to reach terminal branches;
    ///      it is not an operation available to Unight in production.
    /// @param tick Replacement pool tick.
    function setPoolTick(int24 tick) internal {
        bytes32 poolStateSlot = keccak256(abi.encodePacked(POOL_ID, bytes32(uint256(6))));
        uint256 word = uint256(vm.load(POOL_MANAGER, poolStateSlot));
        word = (word & ~uint256(type(uint160).max)) | uint256(TickMath.getSqrtPriceAtTick(tick));
        word = (word & ~(uint256(type(uint24).max) << 160)) | (uint256(uint24(int24(tick))) << 160);
        vm.store(POOL_MANAGER, poolStateSlot, bytes32(word));
    }
}

/// @notice Fork-local controllable oracle used only to exercise account policy
///         behavior; no production dormancy oracle is currently deployed.
contract ForkDormancyOracle is IDormancyOracle {
    /// @notice Whether the test oracle accepts the position as dormant.
    bool public dormant;

    /// @param initialDormant Initial result returned by {isDormant}.
    constructor(bool initialDormant) {
        dormant = initialDormant;
    }

    /// @notice Changes the result returned by {isDormant}.
    /// @param value New dormancy result.
    function setDormant(bool value) external {
        dormant = value;
    }

    /// @inheritdoc IDormancyOracle
    function isDormant(bytes32, int24, int24, uint24, uint32) external view returns (bool) {
        return dormant;
    }
}
