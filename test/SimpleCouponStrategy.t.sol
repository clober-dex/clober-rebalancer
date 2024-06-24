// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "clober-dex/v2-core/BookManager.sol";
import "solmate/test/utils/mocks/MockERC20.sol";

import "../src/SimpleCouponStrategy.sol";
import "./mocks/OpenRouter.sol";

contract SimpleCouponStrategyTest is Test {
    using EpochLibrary for Epoch;
    using BookIdLibrary for IBookManager.BookKey;
    using TickLibrary for Tick;

    IBookManager public bookManager;
    OpenRouter public cloberOpenRouter;
    SimpleCouponStrategy public strategy;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    IBookManager.BookKey public keyA;
    IBookManager.BookKey public keyB;
    bytes32 public key;

    function setUp() public {
        vm.warp(1710317879);
        bookManager = new BookManager(address(this), address(0x123), "URI", "URI", "Name", "SYMBOL");
        cloberOpenRouter = new OpenRouter(bookManager);

        tokenA = new MockERC20("Token A", "TKA", 18);
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

        strategy = new SimpleCouponStrategy(IRebalancer(address(this)), bookManager, address(this));

        key = bytes32(uint256(123123));

        strategy.setCouponStrategy(key, EpochLibrary.current().add(1), 98534533154674428335, 146389476364791594973); // 4%, 6%
    }

    // @dev mocking
    function getBookPairs(bytes32) external view returns (BookId bookIdA, BookId bookIdB) {
        return (keyA.toId(), keyB.toId());
    }

    function testCalculateCouponPriceMinimum() public {
        Epoch current = EpochLibrary.current();
        vm.warp(current.endTime() - 1);
        uint96 rate = 98534533154674428335; // 1.243 * 1e9
        uint256 p = strategy.calculateCouponPrice(current, rate);
        assertEq(p, 98534533154674428335);
        assertEq(FixedPointMathLib.mulDivDown(p, 1e18, 1 << 96), 1243680656);
    }

    function testCalculateCouponPrice() public view {
        uint96 rate = 98534533154674428335; // 1.243 * 1e9
        Epoch current = EpochLibrary.current();

        assertEq(strategy.calculateCouponPrice(current.sub(1), rate), 0);
        uint256 p = strategy.calculateCouponPrice(current, rate);
        assertEq(p, 158969348697323155774989773);
        assertEq(FixedPointMathLib.mulDivDown(p, 1e18, 1 << 96), 2006475269052240);
        p = strategy.calculateCouponPrice(current.add(1), rate);
        assertEq(p, 256326894903603305869921641);
        assertEq(FixedPointMathLib.mulDivDown(p, 1e18, 1 << 96), 3235300261538362);
        p = strategy.calculateCouponPrice(current.add(11), rate);
        assertEq(p, 247208994008569190377949630);
        assertEq(FixedPointMathLib.mulDivDown(p, 1e18, 1 << 96), 3120216172678009);

        uint256 sum;
        for (uint16 i; i < 13; ++i) {
            uint256 price = strategy.calculateCouponPrice(current.add(i).sub(1), rate);
            sum += price;
        }
        assertEq(sum, 3059889965301269778927184551);
        assertEq(FixedPointMathLib.mulDivDown(sum, 1e18, 1 << 96), 38621241086468001);
    }

    function testCalculateCouponTick() public view {
        (Tick bidTick, Tick askTick) = strategy.calculateCouponTick(key);
        assertEq(Tick.unwrap(bidTick), -57340, "BID_TICK");
        assertEq(Tick.unwrap(askTick), 53363, "ASK_TICK");
        assertEq(FixedPointMathLib.mulDivDown(bidTick.toPrice(), 1e18, 1 << 128), 3235042158527404, "BID_PRICE");
        assertEq(FixedPointMathLib.mulDivDown(askTick.toPrice(), 1e18, 1 << 128), 207687221007653627846, "ASK_PRICE");
    }

    function testConvertAmount() public view {
        uint256 amount = 1e18;

        assertEq(strategy.convertAmount(key, amount, true), 309114982432006754093, "A -> B");
        assertEq(strategy.convertAmount(key, amount, false), 4814932739473404, "B -> A");
    }

    function testComputeAllocation() public view {
        (SimpleCouponStrategy.Order[] memory bids, SimpleCouponStrategy.Order[] memory asks) =
            strategy.computeOrders(key, 1e18 + 123, 1e15 - 4435);
        assertEq(bids.length, 1, "BIDS_LENGTH");
        assertEq(asks.length, 1, "ASKS_LENGTH");
        assertEq(Tick.unwrap(bids[0].tick), -57340, "BID_TICK");
        assertEq(bids[0].rawAmount, 1001001, "BID_AMOUNT");
        assertEq(Tick.unwrap(asks[0].tick), 53363, "ASK_TICK");
        assertEq(asks[0].rawAmount, 999, "ASK_AMOUNT");
    }

    function testSetCouponStrategy() public {
        Epoch epoch = EpochLibrary.current().add(2);
        uint96 bidRate = 123456789;
        uint96 askRate = 987654321;

        strategy.setCouponStrategy(key, epoch, bidRate, askRate);

        SimpleCouponStrategy.CouponStrategy memory s = strategy.getCouponStrategy(key);
        assertEq(Epoch.unwrap(s.epoch), Epoch.unwrap(epoch), "EPOCH");
        assertEq(s.bidRate, bidRate, "BID_RATE");
        assertEq(s.askRate, askRate, "ASK_RATE");
    }

    function testSetCouponStrategyAccess() public {
        Epoch epoch = EpochLibrary.current().add(2);
        uint96 bidRate = 123456789;
        uint96 askRate = 987654321;

        vm.prank(address(123));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, (address(123))));
        strategy.setCouponStrategy(key, epoch, bidRate, askRate);
    }
}
