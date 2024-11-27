// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "clober-dex/v2-core/BookManager.sol";
import "solmate/test/utils/mocks/MockERC20.sol";

import "../src/SimpleOracleStrategy.sol";
import "../src/interfaces/IRebalancer.sol";
import "./mocks/MockOracle.sol";
import "./mocks/OpenRouter.sol";

contract SimpleOracleStrategyTest is Test {
    using BookIdLibrary for IBookManager.BookKey;
    using TickLibrary for Tick;

    IBookManager public bookManager;
    OpenRouter public cloberOpenRouter;
    MockOracle public oracle;
    SimpleOracleStrategy public strategy;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    IBookManager.BookKey public keyA;
    IBookManager.BookKey public keyB;
    uint256 public reserveA;
    uint256 public reserveB;
    uint256 public cancelableA;
    uint256 public cancelableB;
    bytes32 public key;

    function setUp() public {
        vm.warp(1710317879);
        bookManager = new BookManager(address(this), address(0x123), "URI", "URI", "Name", "SYMBOL");
        cloberOpenRouter = new OpenRouter(bookManager);

        oracle = new MockOracle();

        tokenA = new MockERC20("Token A", "TKA", 6);
        tokenB = new MockERC20("Token B", "TKB", 18);

        keyA = IBookManager.BookKey({
            base: Currency.wrap(address(tokenB)),
            unitSize: 1,
            quote: Currency.wrap(address(tokenA)),
            makerPolicy: FeePolicyLibrary.encode(true, -1000),
            hooks: IHooks(address(0)),
            takerPolicy: FeePolicyLibrary.encode(true, 1200)
        });
        keyB = IBookManager.BookKey({
            base: Currency.wrap(address(tokenA)),
            unitSize: 1e12,
            quote: Currency.wrap(address(tokenB)),
            makerPolicy: FeePolicyLibrary.encode(true, 1000),
            hooks: IHooks(address(0)),
            takerPolicy: FeePolicyLibrary.encode(true, 1200)
        });
        cloberOpenRouter.open(keyA, "");
        cloberOpenRouter.open(keyB, "");

        strategy = new SimpleOracleStrategy(oracle, IRebalancer(address(this)), bookManager, address(this));

        key = bytes32(uint256(123123));

        strategy.setConfig(
            key,
            ISimpleOracleStrategy.Config({
                referenceThreshold: 40000, // 4%
                rebalanceThreshold: 100000, // 10%
                rateA: 10000, // 1%
                rateB: 10000, // 1%
                minRateA: 3000, // 0.3%
                minRateB: 3000, // 0.3%
                priceThresholdA: 30000, // 3%
                priceThresholdB: 30000 // 3%
            })
        );

        _setReferencePrices(1e8, 3400 * 1e8);
        strategy.setOperator(address(this), true);
    }

    // @dev mocking
    function getBookPairs(bytes32) external view returns (BookId bookIdA, BookId bookIdB) {
        return (keyA.toId(), keyB.toId());
    }

    function _setReferencePrices(uint256 priceA, uint256 priceB) internal {
        oracle.setAssetPrice(address(tokenA), priceA);
        oracle.setAssetPrice(address(tokenB), priceB);
    }

    function testIsOraclePriceValid() public {
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905), 1000000);
        assertTrue(strategy.isOraclePriceValid(key));
    }

    function testIsOraclePriceValidWhenReferenceOracleThrowError() public {
        oracle.setValidity(false);

        assertFalse(strategy.isOraclePriceValid(key));
    }

    function testIsOraclePriceValidWhenOraclePriceIsOutOfRange() public {
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905), 1000000);
        oracle.setAssetPrice(address(tokenB), 1230 * 1e8);
        assertFalse(strategy.isOraclePriceValid(key));
    }

    function testUpdatePosition() public {
        vm.expectEmit(address(strategy));
        emit ISimpleOracleStrategy.UpdatePosition(key, 3367_73789741, Tick.wrap(-195304), Tick.wrap(194905), 1000000);
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905), 1000000);

        SimpleOracleStrategy.Position memory position = strategy.getPosition(key);
        assertEq(position.oraclePrice, 3367_73789741);
        assertEq(Tick.unwrap(position.tickA), -195304);
        assertEq(Tick.unwrap(position.tickB), 194905);

        oracle.setAssetPrice(address(tokenB), 1230 * 1e8);
        vm.expectEmit(address(strategy));
        emit ISimpleOracleStrategy.UpdatePosition(key, 1238_98347920, Tick.wrap(-205304), Tick.wrap(204905), 1000000);
        strategy.updatePosition(key, Tick.wrap(-205100).toPrice(), Tick.wrap(-205304), Tick.wrap(204905), 1000000);

        position = strategy.getPosition(key);
        assertEq(position.oraclePrice, 1238_98347920);
        assertEq(Tick.unwrap(position.tickA), -205304);
        assertEq(Tick.unwrap(position.tickB), 204905);
    }

    function testUpdatePositionRevertWhenOraclePriceIsInvalid() public {
        oracle.setAssetPrice(address(tokenB), 1230 * 1e8);
        vm.expectRevert(abi.encodeWithSelector(ISimpleOracleStrategy.InvalidOraclePrice.selector));
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905), 1000000);
    }

    function testUpdatePositionOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(ISimpleOracleStrategy.NotOperator.selector));
        vm.prank(address(123));
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905), 1000000);
    }

    function testUpdatePositionWhenBidPriceIsHigherThanAskPrice() public {
        vm.expectRevert(abi.encodeWithSelector(ISimpleOracleStrategy.InvalidPrice.selector));
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(195405), 1000000);
    }

    function testUpdatePositionWhenPricesAreTooFarFromOraclePrice() public {
        ISimpleOracleStrategy.Config memory config = strategy.getConfig(key);
        config.priceThresholdA = 1e4; // 1%
        config.priceThresholdB = 1e5; // 10%
        strategy.setConfig(key, config);

        vm.expectRevert(abi.encodeWithSelector(ISimpleOracleStrategy.ExceedsThreshold.selector));
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-194954), Tick.wrap(194905), 1000000);

        config.priceThresholdA = 1e5; // 10%
        config.priceThresholdB = 1e4; // 1%
        strategy.setConfig(key, config);

        vm.expectRevert(abi.encodeWithSelector(ISimpleOracleStrategy.ExceedsThreshold.selector));
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(195255), 1000000);
    }

    function testComputeOrders() public {
        // 1 ETH = 3367 USDT
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905), 1000000);

        reserveA = 10000 * 1e6;
        reserveB = 3 * 1e18;
        (IStrategy.Order[] memory ordersA, IStrategy.Order[] memory ordersB) = strategy.computeOrders(key);
        assertEq(ordersA.length, 1);
        assertEq(ordersB.length, 1);
        assertEq(Tick.unwrap(ordersA[0].tick), -195304);
        assertEq(Tick.unwrap(ordersB[0].tick), 194905);
        assertEq(ordersA[0].rawAmount, 100100100);
        assertEq(ordersB[0].rawAmount, 29663);

        reserveA = 10000 * 1e6;
        reserveB = 1 * 1e18;
        (ordersA, ordersB) = strategy.computeOrders(key);
        assertEq(ordersA.length, 1);
        assertEq(ordersB.length, 1);
        assertEq(Tick.unwrap(ordersA[0].tick), -195304);
        assertEq(Tick.unwrap(ordersB[0].tick), 194905);
        assertEq(ordersA[0].rawAmount, 33711089);
        assertEq(ordersB[0].rawAmount, 9990);

        reserveA = 1000 * 1e6;
        reserveB = 3 * 1e18;
        (ordersA, ordersB) = strategy.computeOrders(key);
        assertEq(ordersA.length, 1);
        assertEq(ordersB.length, 1);
        assertEq(Tick.unwrap(ordersA[0].tick), -195304);
        assertEq(Tick.unwrap(ordersB[0].tick), 194905);
        assertEq(ordersA[0].rawAmount, 10010010);
        assertEq(ordersB[0].rawAmount, 8991);

        strategy.rebalanceHook(address(this), key, ordersA, ordersB);
        (uint256 ra, uint256 rb) = strategy.getLastRawAmount(key);
        assertEq(ra, 10010010);
        assertEq(rb, 8991);

        cancelableA = 1001001;
        cancelableB = 899100000000001;
        (ordersA, ordersB) = strategy.computeOrders(key);
        assertEq(ordersA.length, 0);
        assertEq(ordersB.length, 0);

        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905), 1000000);

        (ra, rb) = strategy.getLastRawAmount(key);
        assertEq(ra, 0);
        assertEq(rb, 0);

        (ordersA, ordersB) = strategy.computeOrders(key);
        assertEq(ordersA.length, 1);
        assertEq(ordersB.length, 1);
        assertEq(Tick.unwrap(ordersA[0].tick), -195304);
        assertEq(Tick.unwrap(ordersB[0].tick), 194905);
        assertEq(ordersA[0].rawAmount, 10020030);
        assertEq(ordersB[0].rawAmount, 8993);
    }

    function testComputeOrdersWhenOraclePriceIsInvalid() public {
        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905), 1000000);
        oracle.setValidity(false);

        vm.expectRevert(abi.encodeWithSelector(ISimpleOracleStrategy.InvalidOraclePrice.selector));
        (IStrategy.Order[] memory ordersA, IStrategy.Order[] memory ordersB) = strategy.computeOrders(key);
    }

    function testPause() public {
        vm.expectEmit(address(strategy));
        emit ISimpleOracleStrategy.Pause(key);
        strategy.pause(key);

        SimpleOracleStrategy.Position memory position = strategy.getPosition(key);
        assertTrue(position.paused);
        assertTrue(strategy.isPaused(key));

        vm.expectRevert(abi.encodeWithSelector(ISimpleOracleStrategy.Paused.selector));
        strategy.computeOrders(key);

        (uint256 ra, uint256 rb) = strategy.getLastRawAmount(key);
        assertEq(ra, 0);
        assertEq(rb, 0);
    }

    function testPauseOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(ISimpleOracleStrategy.NotOperator.selector));
        vm.prank(address(123));
        strategy.pause(key);
    }

    function testUnpause() public {
        strategy.pause(key);

        strategy.updatePosition(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905), 1000000);

        vm.expectEmit(address(strategy));
        emit ISimpleOracleStrategy.Unpause(key);
        strategy.unpause(key);

        SimpleOracleStrategy.Position memory position = strategy.getPosition(key);
        assertFalse(position.paused);
        assertFalse(strategy.isPaused(key));

        strategy.computeOrders(key);
    }

    function testUnpauseOwnership() public {
        strategy.pause(key);

        vm.expectRevert(abi.encodeWithSelector(ISimpleOracleStrategy.NotOperator.selector));
        vm.prank(address(123));
        strategy.unpause(key);
    }

    function getLiquidity(bytes32)
        public
        view
        returns (IRebalancer.Liquidity memory liquidityA, IRebalancer.Liquidity memory liquidityB)
    {
        return (
            IRebalancer.Liquidity({reserve: reserveA, claimable: 0, cancelable: cancelableA}),
            IRebalancer.Liquidity({reserve: reserveB, claimable: 0, cancelable: cancelableB})
        );
    }
}
