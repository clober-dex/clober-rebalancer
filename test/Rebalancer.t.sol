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
        RebalancerWrapper(payable(address(uint160(Hooks.BEFORE_MAKE_FLAG | Hooks.AFTER_TAKE_FLAG))));

    function setUp() public {
        vm.warp(1710317879);
        bookManager = new BookManager(address(this), address(0x123), "URI", "URI", "Name", "SYMBOL");
        cloberOpenRouter = new OpenRouter(bookManager);

        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

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

        strategy = new SimpleCouponStrategy(rebalancer, bookManager, address(this));

        keyA = IBookManager.BookKey({
            base: Currency.wrap(address(tokenB)),
            unit: 1e12,
            quote: Currency.wrap(address(tokenA)),
            makerPolicy: FeePolicyLibrary.encode(true, -1000),
            hooks: rebalancer,
            takerPolicy: FeePolicyLibrary.encode(true, 1200)
        });
        unopenedKeyA = keyA;
        unopenedKeyA.unit = 1e13;
        keyB = IBookManager.BookKey({
            base: Currency.wrap(address(tokenA)),
            unit: 1e12,
            quote: Currency.wrap(address(tokenB)),
            makerPolicy: FeePolicyLibrary.encode(false, -1000),
            hooks: rebalancer,
            takerPolicy: FeePolicyLibrary.encode(false, 1200)
        });
        unopenedKeyB = keyB;
        unopenedKeyB.unit = 1e13;

        key = rebalancer.open(keyA, keyB, address(strategy), 3600);

        strategy.setCouponStrategy(key, EpochLibrary.current().add(1), 98534533154674428335, 146389476364791594973); // 4%, 6%

        tokenA.mint(address(this), 1e27);
        tokenB.mint(address(this), 1e27);
        tokenA.approve(address(rebalancer), type(uint256).max);
        tokenB.approve(address(rebalancer), type(uint256).max);
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
        (BookId idA, BookId idB) = rebalancer.getBookPairs(key1);
        assertEq(BookId.unwrap(idA), BookId.unwrap(bookIdA), "PAIRS_A");
        assertEq(BookId.unwrap(idB), BookId.unwrap(bookIdB), "PAIRS_B");

        vm.revertTo(snapshotId);
        vm.expectEmit(false, true, true, true, address(rebalancer));
        emit IRebalancer.Open(bytes32(0), bookIdB, bookIdA, address(strategy), 3600);
        bytes32 key2 = rebalancer.open(unopenedKeyB, unopenedKeyA, address(strategy), 3600);
        pool = rebalancer.getPool(key1);
        assertEq(BookId.unwrap(pool.bookIdA), BookId.unwrap(bookIdB), "POOL_A");
        assertEq(BookId.unwrap(pool.bookIdB), BookId.unwrap(bookIdA), "POOL_B");
        (idA, idB) = rebalancer.getBookPairs(key1);
        assertEq(BookId.unwrap(idA), BookId.unwrap(bookIdB), "PAIRS_A");
        assertEq(BookId.unwrap(idB), BookId.unwrap(bookIdA), "PAIRS_B");

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

    function testMintInitially() public {
        assertEq(rebalancer.totalSupply(uint256(key)), 0, "INITIAL_SUPPLY");

        uint256 snapshotId = vm.snapshot();

        vm.expectEmit(address(rebalancer));
        emit IRebalancer.Mint(address(this), key, 12341234, 0, 12341234);
        rebalancer.mint(key, 12341234, 0);
        assertEq(rebalancer.totalSupply(uint256(key)), 12341234, "AFTER_SUPPLY_0");
        assertEq(rebalancer.getPool(key).reserveA, 12341234, "RESERVE_A_0");
        assertEq(rebalancer.getPool(key).reserveB, 0, "RESERVE_B_0");
        (uint256 liquidityA, uint256 liquidityB) = rebalancer.getLiquidity(key);
        assertEq(liquidityA, 12341234, "LIQUIDITY_A_0");
        assertEq(liquidityB, 0, "LIQUIDITY_B_0");
        assertEq(rebalancer.balanceOf(address(this), uint256(key)), 12341234, "LP_BALANCE_0");

        vm.revertTo(snapshotId);
        vm.expectEmit(address(rebalancer));
        emit IRebalancer.Mint(address(this), key, 0, 1e18, 4814932739473404);
        rebalancer.mint(key, 0, 1e18);
        assertEq(rebalancer.totalSupply(uint256(key)), 4814932739473404, "AFTER_SUPPLY_1");
        assertEq(rebalancer.getPool(key).reserveA, 0, "RESERVE_A_1");
        assertEq(rebalancer.getPool(key).reserveB, 1e18, "RESERVE_B_1");
        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);
        assertEq(liquidityA, 0, "LIQUIDITY_A_1");
        assertEq(liquidityB, 1e18, "LIQUIDITY_B_1");
        assertEq(rebalancer.balanceOf(address(this), uint256(key)), 4814932739473404, "LP_BALANCE_1");

        vm.revertTo(snapshotId);
        vm.expectEmit(address(rebalancer));
        emit IRebalancer.Mint(address(this), key, 1e18, 1e18, 1004814932739473404);
        rebalancer.mint(key, 1e18, 1e18);
        assertEq(rebalancer.totalSupply(uint256(key)), 1004814932739473404, "AFTER_SUPPLY_2");
        assertEq(rebalancer.getPool(key).reserveA, 1e18, "RESERVE_A_2");
        assertEq(rebalancer.getPool(key).reserveB, 1e18, "RESERVE_B_2");
        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);
        assertEq(liquidityA, 1e18, "LIQUIDITY_A_2");
        assertEq(liquidityB, 1e18, "LIQUIDITY_B_2");
        assertEq(rebalancer.balanceOf(address(this), uint256(key)), 1004814932739473404, "LP_BALANCE_2");
    }

    function testMint() public {
        rebalancer.mint(key, 1e18, 1e18);
        assertEq(rebalancer.totalSupply(uint256(key)), 1004814932739473404, "BEFORE_SUPPLY");

        IRebalancer.Pool memory beforePool = rebalancer.getPool(key);
        IRebalancer.Pool memory afterPool = beforePool;
        (uint256 beforeLiquidityA, uint256 beforeLiquidityB) = rebalancer.getLiquidity(key);
        (uint256 afterLiquidityA, uint256 afterLiquidityB) = (beforeLiquidityA, beforeLiquidityB);
        uint256 beforeLpBalance = rebalancer.balanceOf(address(this), uint256(key));
        uint256 beforeSupply = rebalancer.totalSupply(uint256(key));

        vm.expectEmit(address(rebalancer));
        emit IRebalancer.Mint(address(this), key, 1e18 / 2, 1e18 / 2, 1004814932739473404 / 2);
        rebalancer.mint(key, 1e18 / 2, 1e18 / 2);
        afterPool = rebalancer.getPool(key);
        (afterLiquidityA, afterLiquidityB) = rebalancer.getLiquidity(key);
        assertEq(rebalancer.totalSupply(uint256(key)), beforeSupply + 1004814932739473404 / 2, "AFTER_SUPPLY_0");
        assertEq(afterPool.reserveA, beforePool.reserveA + 1e18 / 2, "RESERVE_A_0");
        assertEq(afterPool.reserveB, beforePool.reserveB + 1e18 / 2, "RESERVE_B_0");
        assertEq(afterLiquidityA, beforeLiquidityA + 1e18 / 2, "LIQUIDITY_A_0");
        assertEq(afterLiquidityB, beforeLiquidityB + 1e18 / 2, "LIQUIDITY_B_0");
        assertEq(
            rebalancer.balanceOf(address(this), uint256(key)), beforeLpBalance + 1004814932739473404 / 2, "LP_BALANCE_0"
        );

        beforePool = afterPool;
        (beforeLiquidityA, beforeLiquidityB) = (afterLiquidityA, afterLiquidityB);
        beforeLpBalance = rebalancer.balanceOf(address(this), uint256(key));
        beforeSupply = rebalancer.totalSupply(uint256(key));

        vm.expectEmit(address(rebalancer));
        emit IRebalancer.Mint(address(this), key, 1e18, 0, 1001570915781815141);
        rebalancer.mint(key, 1e18, 0);
        afterPool = rebalancer.getPool(key);
        (afterLiquidityA, afterLiquidityB) = rebalancer.getLiquidity(key);
        assertEq(rebalancer.totalSupply(uint256(key)), beforeSupply + 1001570915781815141, "AFTER_SUPPLY_1");
        assertEq(afterPool.reserveA, beforePool.reserveA + 1e18, "RESERVE_A_1");
        assertEq(afterPool.reserveB, beforePool.reserveB, "RESERVE_B_1");
        assertEq(afterLiquidityA, beforeLiquidityA + 1e18, "LIQUIDITY_A_1");
        assertEq(afterLiquidityB, beforeLiquidityB, "LIQUIDITY_B_1");
        assertEq(
            rebalancer.balanceOf(address(this), uint256(key)), beforeLpBalance + 1001570915781815141, "LP_BALANCE_1"
        );

        beforePool = afterPool;
        (beforeLiquidityA, beforeLiquidityB) = (afterLiquidityA, afterLiquidityB);
        beforeLpBalance = rebalancer.balanceOf(address(this), uint256(key));
        beforeSupply = rebalancer.totalSupply(uint256(key));

        vm.expectEmit(address(rebalancer));
        emit IRebalancer.Mint(address(this), key, 0, 1e18, 4812184660629696);
        rebalancer.mint(key, 0, 1e18);
        afterPool = rebalancer.getPool(key);
        (afterLiquidityA, afterLiquidityB) = rebalancer.getLiquidity(key);
        assertEq(rebalancer.totalSupply(uint256(key)), beforeSupply + 4812184660629696, "AFTER_SUPPLY_2");
        assertEq(afterPool.reserveA, beforePool.reserveA, "RESERVE_A_2");
        assertEq(afterPool.reserveB, beforePool.reserveB + 1e18, "RESERVE_B_2");
        assertEq(afterLiquidityA, beforeLiquidityA, "LIQUIDITY_A_2");
        assertEq(afterLiquidityB, beforeLiquidityB + 1e18, "LIQUIDITY_B_2");
        assertEq(rebalancer.balanceOf(address(this), uint256(key)), beforeLpBalance + 4812184660629696, "LP_BALANCE_2");
    }

    function testBurn() public {
        rebalancer.mint(key, 1e18 + 141231, 1e21 + 241245);

        (uint256 beforeLiquidityA, uint256 beforeLiquidityB) = rebalancer.getLiquidity(key);
        uint256 beforeLpBalance = rebalancer.balanceOf(address(this), uint256(key));
        uint256 beforeSupply = rebalancer.totalSupply(uint256(key));
        uint256 beforeABalance = tokenA.balanceOf(address(this));
        uint256 beforeBBalance = tokenB.balanceOf(address(this));

        vm.expectEmit(address(rebalancer));
        emit IRebalancer.Burn(
            address(this), key, uint256(1e18 + 141231) / 2, uint256(1e21 + 241245) / 2, beforeSupply / 2
        );
        rebalancer.burn(key, beforeSupply / 2);

        IRebalancer.Pool memory afterPool = rebalancer.getPool(key);
        (uint256 afterLiquidityA, uint256 afterLiquidityB) = rebalancer.getLiquidity(key);
        assertEq(rebalancer.totalSupply(uint256(key)), beforeSupply - beforeSupply / 2, "AFTER_SUPPLY");
        assertLt(afterPool.reserveA, keyA.unit, "RESERVE_A"); // 500000070616
        assertLt(afterPool.reserveB, keyB.unit, "RESERVE_B"); // 120623
        assertEq(afterLiquidityA, beforeLiquidityA - uint256(1e18 + 141231) / 2, "LIQUIDITY_A");
        assertEq(afterLiquidityB, beforeLiquidityB - uint256(1e21 + 241245) / 2, "LIQUIDITY_B");
        assertEq(rebalancer.balanceOf(address(this), uint256(key)), beforeLpBalance - beforeSupply / 2, "LP_BALANCE");
        assertEq(tokenA.balanceOf(address(this)) - beforeABalance, uint256(1e18 + 141231) / 2, "A_BALANCE");
        assertEq(tokenB.balanceOf(address(this)) - beforeBBalance, uint256(1e21 + 241245) / 2, "B_BALANCE");
    }

    function testRebalance() public {}

    function testRebalanceAfterSomeOrdersHaveTaken() public {}

    function testRebalanceShouldSkipIfThresholdNotReached() public {}

    function testRebalanceRevertUnknownBook() public {}
}
