// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "clober-dex/v2-core/BookManager.sol";
import "solmate/test/utils/mocks/MockERC20.sol";

import "../src/SimpleOracleStrategy.sol";
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
            unitSize: 1e12,
            quote: Currency.wrap(address(tokenA)),
            makerPolicy: FeePolicyLibrary.encode(true, -1000),
            hooks: IHooks(address(0)),
            takerPolicy: FeePolicyLibrary.encode(true, 1200)
        });
        keyB = IBookManager.BookKey({
            base: Currency.wrap(address(tokenA)),
            unitSize: 1e12,
            quote: Currency.wrap(address(tokenB)),
            makerPolicy: FeePolicyLibrary.encode(false, -1000),
            hooks: IHooks(address(0)),
            takerPolicy: FeePolicyLibrary.encode(false, 1200)
        });
        cloberOpenRouter.open(keyA, "");
        cloberOpenRouter.open(keyB, "");

        strategy = new SimpleOracleStrategy(oracle, IRebalancer(address(this)), bookManager, address(this));

        key = bytes32(uint256(123123));

        strategy.setConfig(
            key,
            SimpleOracleStrategy.Config({
                referenceThreshold: 40000, // 4%
                rateA: 10000, // 1%
                rateB: 10000, // 1%
                minRateA: 3000, // 0.3%
                minRateB: 3000, // 0.3%
                priceThresholdA: 30000, // 3%
                priceThresholdB: 30000 // 3%
            })
        );

        _setReferencePrices(1e8, 3400 * 1e8);
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
        strategy.updatePrice(key, Tick.wrap(-195100).toPrice(), Tick.wrap(-195304), Tick.wrap(194905));
        assertTrue(strategy.isOraclePriceValid(key));
    }

    function testIsOraclePriceValidWhenReferenceOracleThrowError() public {
        oracle.setValidity(false);

        assertFalse(strategy.isOraclePriceValid(key));
    }

    function testIsOraclePriceValidWhenOraclePriceIsOutOfRange() public {
        strategy.updatePrice(key, Tick.wrap(-1951).toPrice(), Tick.wrap(-1953), Tick.wrap(1949));
        assertFalse(strategy.isOraclePriceValid(key));
    }

    function testUpdatePrice() public {}

    function testUpdatePriceWithInvalidPrices() public {}

    function computeOrders() public {}

    function computeOrdersWhenOraclePriceIsInvalid() public {}
}
