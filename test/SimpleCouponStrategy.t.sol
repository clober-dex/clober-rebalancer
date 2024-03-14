// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BookManager} from "clober-dex/v2-core/BookManager.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

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

    function setUp() public {
        vm.warp(1710317879);
        bookManager = new BookManager(address(this), address(0x123), "URI", "URI", "Name", "SYMBOL");
        cloberOpenRouter = new OpenRouter(bookManager);

        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        keyA = IBookManager.BookKey({
            base: Currency.wrap(address(tokenB)),
            unit: 1e12,
            quote: Currency.wrap(address(tokenA)),
            makerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: IHooks(address(0)),
            takerPolicy: FeePolicyLibrary.encode(true, 0)
        });
        keyB = IBookManager.BookKey({
            base: Currency.wrap(address(tokenA)),
            unit: 1e12,
            quote: Currency.wrap(address(tokenB)),
            makerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: IHooks(address(0)),
            takerPolicy: FeePolicyLibrary.encode(true, 0)
        });
        cloberOpenRouter.open(keyA, "");
        cloberOpenRouter.open(keyB, "");

        strategy = new SimpleCouponStrategy(bookManager, address(this));
        strategy.setCouponStrategy(
            keyA.toId(), keyB.toId(), EpochLibrary.current().add(1), 98534533154674428335, 146389476364791594973
        ); // 4%, 6%
    }

    function testCalculateCouponPrice() public {
        uint96 rate = 98534533154674428335; // 1.243 * 1e9
        Epoch current = EpochLibrary.current();

        assertEq(strategy.calculateCouponPrice(current.sub(1), rate), 0);
        assertEq(strategy.calculateCouponPrice(current, rate), 158969348697323155774989773);
        assertEq(strategy.calculateCouponPrice(current.add(1), rate), 256326894903603305869921641);
        assertEq(strategy.calculateCouponPrice(current.add(11), rate), 247208994008569190377949630);

        uint256 sum;
        for (uint16 i; i < 13; ++i) {
            uint256 price = strategy.calculateCouponPrice(current.add(i).sub(1), rate);
            sum += price;
        }
        assertEq(sum, 3059889965301269778927184551);
        assertEq(FixedPointMathLib.mulDivDown(sum, 1e18, 1 << 96), 38621241086468001);
    }

    function testCalculateCouponTick() public {
        (Tick bidTick, Tick askTick) = strategy.calculateCouponTick(keyA.toId(), keyB.toId());
        assertEq(Tick.unwrap(bidTick), -57340);
        assertEq(Tick.unwrap(askTick), 53363);
        assertEq(FixedPointMathLib.mulDivDown(bidTick.toPrice(), 1e18, 1 << 128), 3235042158527404);
        assertEq(FixedPointMathLib.mulDivDown(askTick.toPrice(), 1e18, 1 << 128), 207687221007653627846);
    }
}
