// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "clober-dex/v2-core/BookManager.sol";
import "solmate/test/utils/mocks/MockERC20.sol";

import "../src/Minter.sol";
import "./mocks/TakeRouter.sol";
import "../src/SimpleOracleStrategy.sol";
import "./mocks/OpenRouter.sol";
import "./mocks/MockOracle.sol";
import "../src/mocks/MockSwap.sol";
import "../src/TimeEscrow.sol";

contract MinterTest is Test {
    IBookManager public bookManager;
    SimpleOracleStrategy public strategy;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    IBookManager.BookKey public keyA;
    IBookManager.BookKey public keyB;
    bytes32 public key;
    ITimeEscrow public timeEscrow;
    Rebalancer public rebalancer;
    OpenRouter public cloberOpenRouter;
    MockOracle public oracle;
    TakeRouter public takeRouter;
    MockSwap public mockSwap;
    Minter public minter;

    ERC20PermitParams public emptyParams;
    address public RECEIVER = address(0x132);

    function setUp() public {
        bookManager = new BookManager(address(this), address(0x123), "URI", "URI", "Name", "SYMBOL");
        cloberOpenRouter = new OpenRouter(bookManager);

        oracle = new MockOracle();

        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        address timeEscrowTemplate = address(new TimeEscrow());
        timeEscrow = ITimeEscrow(
            address(
                new ERC1967Proxy(
                    timeEscrowTemplate, abi.encodeWithSelector(TimeEscrow.initialize.selector, address(this))
                )
            )
        );

        address rebalancerTemplate = address(new Rebalancer(bookManager, address(timeEscrow)));
        rebalancer = Rebalancer(
            payable(
                address(
                    new ERC1967Proxy(
                        rebalancerTemplate,
                        abi.encodeWithSelector(Rebalancer.initialize.selector, address(this), 6 hours)
                    )
                )
            )
        );

        strategy = new SimpleOracleStrategy(oracle, rebalancer, bookManager, address(this));

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

        key = rebalancer.open(keyA, keyB, 0x0, address(strategy));

        strategy.setConfig(
            key,
            ISimpleOracleStrategy.Config({
                referenceThreshold: 40000, // 4%
                rebalanceThreshold: 1000000, // 100%
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

        takeRouter = new TakeRouter(bookManager);
        tokenA.approve(address(takeRouter), type(uint256).max);
        tokenB.approve(address(takeRouter), type(uint256).max);

        mockSwap = new MockSwap();

        minter = new Minter(address(bookManager), payable(rebalancer), address(mockSwap));

        tokenA.mint(address(this), 1e27);
        tokenB.mint(address(this), 1e27);
        tokenA.mint(address(mockSwap), 1e27);
        tokenB.mint(address(mockSwap), 1e27);
        tokenA.approve(address(minter), type(uint256).max);
        tokenB.approve(address(minter), type(uint256).max);
        tokenA.approve(address(rebalancer), type(uint256).max);
        tokenB.approve(address(rebalancer), type(uint256).max);
        tokenA.approve(address(timeEscrow), type(uint256).max);
        tokenB.approve(address(timeEscrow), type(uint256).max);

        rebalancer.mint(key, 1e18, 1e18, 0);
    }

    function _setReferencePrices(uint256 priceA, uint256 priceB) internal {
        oracle.setAssetPrice(address(tokenA), priceA);
        oracle.setAssetPrice(address(tokenB), priceB);
    }

    function testMintWithoutSwapParams() public {
        IMinter.SwapParams memory swapParams;

        uint256 beforeLpBalance = rebalancer.balanceOf(address(this), uint256(key));
        minter.mint(key, 1e18, 1e18, 0, emptyParams, emptyParams, swapParams);

        assertEq(rebalancer.balanceOf(address(this), uint256(key)), beforeLpBalance + 1e18);
    }

    function testMintWithSwap() public {
        IMinter.SwapParams memory swapParams = IMinter.SwapParams({
            inCurrency: Currency.wrap(address(tokenA)),
            amount: 1e18,
            data: abi.encodeWithSelector(mockSwap.swap.selector, address(tokenA), 1e18, address(tokenB), 1e18)
        });

        uint256 beforeLpBalance = rebalancer.balanceOf(address(this), uint256(key));
        minter.mint(key, 2e18, 0, 0, emptyParams, emptyParams, swapParams);

        assertEq(rebalancer.balanceOf(address(this), uint256(key)), beforeLpBalance + 1e18);
    }

    function testUnlockAll() public {
        vm.deal(address(this), 1e28);

        timeEscrow.lock(RECEIVER, address(tokenA), 1e18, block.timestamp + 1 days);
        timeEscrow.lock(RECEIVER, address(tokenA), 1e18, block.timestamp + 1 days);
        timeEscrow.lock{value: 1e18}(RECEIVER, address(0), 1e18, block.timestamp + 1 days);
        timeEscrow.lock(RECEIVER, address(tokenB), 1e18, block.timestamp + 1 days);

        vm.warp(block.timestamp + 1 days);

        IMinter.UnlockParams[] memory params = new IMinter.UnlockParams[](5);
        params[0] = IMinter.UnlockParams(RECEIVER, address(tokenA), 1e18, block.timestamp, 0);
        params[1] = IMinter.UnlockParams(RECEIVER, address(tokenA), 1e18, block.timestamp, 1);
        params[2] = IMinter.UnlockParams(RECEIVER, address(0), 1e18, block.timestamp, 2);
        params[3] = IMinter.UnlockParams(RECEIVER, address(tokenB), 1e18, block.timestamp, 3);
        params[4] = IMinter.UnlockParams(RECEIVER, address(tokenB), 1e18, block.timestamp, 3);

        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlock(RECEIVER, address(tokenA), 1e18, block.timestamp, 0);
        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlock(RECEIVER, address(tokenA), 1e18, block.timestamp, 1);
        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlock(RECEIVER, address(0), 1e18, block.timestamp, 2);
        vm.expectEmit(address(timeEscrow));
        emit ITimeEscrow.Unlock(RECEIVER, address(tokenB), 1e18, block.timestamp, 3);
        bool[] memory results = minter.unlockAll(params);

        assertTrue(results[0]);
        assertTrue(results[1]);
        assertTrue(results[2]);
        assertTrue(results[3]);
        assertFalse(results[4]);
        assertEq(tokenA.balanceOf(RECEIVER), 2e18);
        assertEq(tokenA.balanceOf(address(timeEscrow)), 0);
        assertEq(address(RECEIVER).balance, 1e18);
        assertEq(address(timeEscrow).balance, 0);
        assertEq(tokenB.balanceOf(RECEIVER), 1e18);
        assertEq(tokenB.balanceOf(address(timeEscrow)), 0);
        assertFalse(timeEscrow.isEscrowed(0));
        assertFalse(timeEscrow.isEscrowed(1));
        assertFalse(timeEscrow.isEscrowed(2));
        assertFalse(timeEscrow.isEscrowed(3));
    }
}
