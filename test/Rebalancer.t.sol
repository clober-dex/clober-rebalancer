// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "clober-dex/v2-core/BookManager.sol";
import "solmate/test/utils/mocks/MockERC20.sol";

import "../src/SimpleCouponStrategy.sol";
import "../src/Rebalancer.sol";
import "./mocks/OpenRouter.sol";
import "./mocks/RebalancerWrapper.sol";

contract RebalancerTest is Test {
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
    IBookManager.BookKey public unopenedKeyA;
    IBookManager.BookKey public unopenedKeyB;
    bytes32 public key;
    RebalancerWrapper public rebalancer =
        RebalancerWrapper(payable(address(uint160(Hooks.BEFORE_MAKE_FLAG | Hooks.BEFORE_TAKE_FLAG))));

    function setUp() public {
        vm.warp(1710317879);
        bookManager = new BookManager(address(this), address(0x123), "URI", "URI", "Name", "SYMBOL");
        cloberOpenRouter = new OpenRouter(bookManager);

        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        strategy = new SimpleCouponStrategy(bookManager, address(this));

        vm.record();
        RebalancerWrapper impl = new RebalancerWrapper(bookManager, address(this), rebalancer);
        (, bytes32[] memory writes) = vm.accesses(address(impl));
        vm.etch(address(rebalancer), address(impl).code);
        // for each storage key that was written during the hook implementation, copy the value over
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(address(rebalancer), slot, vm.load(address(impl), slot));
            }
        }

        keyA = IBookManager.BookKey({
            base: Currency.wrap(address(tokenB)),
            unit: 1e12,
            quote: Currency.wrap(address(tokenA)),
            makerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: rebalancer,
            takerPolicy: FeePolicyLibrary.encode(true, 0)
        });
        unopenedKeyA = keyA;
        unopenedKeyA.unit = 1e13;
        keyB = IBookManager.BookKey({
            base: Currency.wrap(address(tokenA)),
            unit: 1e12,
            quote: Currency.wrap(address(tokenB)),
            makerPolicy: FeePolicyLibrary.encode(true, 0),
            hooks: rebalancer,
            takerPolicy: FeePolicyLibrary.encode(true, 0)
        });
        unopenedKeyB = keyB;
        unopenedKeyB.unit = 1e13;

        if (BookId.unwrap(unopenedKeyA.toId()) > BookId.unwrap(unopenedKeyB.toId())) {
            IBookManager.BookKey memory temp = unopenedKeyA;
            unopenedKeyA = unopenedKeyB;
            unopenedKeyB = temp;
        }

        key = rebalancer.open(keyA, keyB, address(strategy), 3600);

        strategy.setCouponStrategy(key, EpochLibrary.current().add(1), 98534533154674428335, 146389476364791594973); // 4%, 6%
    }

    function testOpen() public {
        BookId bookIdA = unopenedKeyA.toId();
        BookId bookIdB = unopenedKeyB.toId();

        uint256 snapshotId = vm.snapshot();
        vm.expectEmit(false, true, true, true, address(rebalancer));
        emit IRebalancer.Open(bytes32(0), bookIdA, bookIdB, address(strategy), 3600);
        bytes32 key1 = rebalancer.open(unopenedKeyA, unopenedKeyB, address(strategy), 3600);
        IRebalancer.Pool memory pool = rebalancer.getPool(key1);
        assertEq(BookId.unwrap(pool.bookIdA), BookId.unwrap(bookIdA), "POOL_A");
        assertEq(BookId.unwrap(pool.bookIdB), BookId.unwrap(bookIdB), "POOL_B");

        vm.revertTo(snapshotId);
        vm.expectEmit(false, true, true, true, address(rebalancer));
        emit IRebalancer.Open(bytes32(0), bookIdA, bookIdB, address(strategy), 3600);
        bytes32 key2 = rebalancer.open(unopenedKeyB, unopenedKeyA, address(strategy), 3600);
        pool = rebalancer.getPool(key1);
        assertEq(BookId.unwrap(pool.bookIdA), BookId.unwrap(bookIdA), "POOL_A");
        assertEq(BookId.unwrap(pool.bookIdB), BookId.unwrap(bookIdB), "POOL_B");

        assertEq(key1, key2, "SAME_KEY");
        assertEq(BookId.unwrap(rebalancer.bookPair(bookIdA)), BookId.unwrap(bookIdB), "PAIR_A");
        assertEq(BookId.unwrap(rebalancer.bookPair(bookIdB)), BookId.unwrap(bookIdA), "PAIR_B");
        assertEq(address(pool.strategy), address(strategy), "STRATEGY");
        assertEq(pool.rebalanceThreshold, 3600, "THRESHOLD");
        assertEq(pool.reserveA, 0, "RESERVE_A");
        assertEq(pool.reserveB, 0, "RESERVE_B");
        assertEq(pool.lastRebalanceTimestamp, 0, "LAST_REBALANCE");
        assertEq(pool.orderListA.length, 0, "ORDER_LIST_A");
        assertEq(pool.orderListB.length, 0, "ORDER_LIST_B");

        (BookId idA, BookId idB) = rebalancer.getBookPairs(key1);
        assertEq(BookId.unwrap(idA), BookId.unwrap(bookIdA), "PAIRS_A");
        assertEq(BookId.unwrap(idB), BookId.unwrap(bookIdB), "PAIRS_B");

        (uint256 liquidityA, uint256 liquidityB) = rebalancer.getLiquidity(key1);
        assertEq(liquidityA, 0, "LIQUIDITY_A");
        assertEq(liquidityB, 0, "LIQUIDITY_B");
    }

    function testOpenShouldCheckCurrencyPair() public {
        unopenedKeyA.quote = Currency.wrap(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(IRebalancer.InvalidBookPair.selector));
        rebalancer.open(unopenedKeyA, unopenedKeyB, address(strategy), 3600);
    }

    function testOpenShouldCheckHooks() public {
        unopenedKeyA.hooks = IHooks(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(IRebalancer.InvalidHook.selector));
        rebalancer.open(unopenedKeyA, unopenedKeyB, address(strategy), 3600);

        unopenedKeyA.hooks = rebalancer;
        unopenedKeyB.hooks = IHooks(address(0x123));
        vm.expectRevert(abi.encodeWithSelector(IRebalancer.InvalidHook.selector));
        rebalancer.open(unopenedKeyA, unopenedKeyB, address(strategy), 3600);
    }

    function testOpenAccess() public {
        vm.expectRevert();
        vm.prank(address(0x123));
        rebalancer.open(unopenedKeyA, unopenedKeyB, address(strategy), 3600);
    }
}
