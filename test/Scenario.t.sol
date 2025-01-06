// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Operator.sol";
import "../src/Minter.sol";

import {IHooks} from "clober-dex/v2-core/interfaces/IHooks.sol";
import {FeePolicyLibrary} from "clober-dex/v2-core/libraries/FeePolicy.sol";
import "../src/SimpleOracleStrategy.sol";
import "./interface/IController.sol";

contract ScenarioTest is Test {
    using BookIdLibrary for IBookManager.BookKey;
    using TickLibrary for Tick;

    address public constant USER1 = address(0x1);
    address public constant USER2 = address(0x2);

    Operator public operator;
    Minter public minter;
    IERC20 public quote;
    IDatastreamOracle public datastreamOracle;
    IRebalancer public rebalancer;
    ISimpleOracleStrategy public strategy;
    IController public controller;
    IBookManager public bookManager;
    bytes32 public key;
    address public owner;
    uint256 public oraclePrice;
    BookId public bidBookId;
    BookId public askBookId;

    function setUp() public {
        uint256 newFork = vm.createFork(vm.envString("FORK_URL"));
        vm.selectFork(newFork);
        vm.rollFork(23818140);

        operator = Operator(0xBB854e8C0f04d919aD770b27015Ee90a9EF31Bf0);
        minter = Minter(payable(0x732547BB8825eAb932Dcda030Fc446bf4A5552f3));
        quote = IERC20(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2); // USDT
        controller = IController(0xe4AB03992e214acfdCD05ccFB5C5C16e3d0Ca371);
        strategy = ISimpleOracleStrategy(0x9092e5f62b27c3eD78feB24A0F2ad6474D26DdA5);

        rebalancer = operator.rebalancer();
        owner = operator.owner();
        datastreamOracle = operator.datastreamOracle();
        bookManager = minter.bookManager();

        vm.prank(0xeE7981C4642dE8d19AeD11dA3bac59277DfD59D7);
        quote.transfer(address(this), 10000000000000);
        vm.deal(address(this), 10000 ether);

        IBookManager.BookKey memory bidBookKey = IBookManager.BookKey(
            Currency.wrap(address(quote)),
            1e12,
            CurrencyLibrary.NATIVE,
            FeePolicyLibrary.encode(true, 0),
            IHooks(address(0)),
            FeePolicyLibrary.encode(true, 0)
        );
        bidBookId = bidBookKey.toId();
        IBookManager.BookKey memory askBookKey = IBookManager.BookKey(
            CurrencyLibrary.NATIVE,
            1,
            Currency.wrap(address(quote)),
            FeePolicyLibrary.encode(true, 0),
            IHooks(address(0)),
            FeePolicyLibrary.encode(true, 0)
        );
        askBookId = askBookKey.toId();

        key = rebalancer.open(bidBookKey, askBookKey, "", address(strategy));
        vm.prank(Ownable(address(strategy)).owner());
        strategy.setConfig(key, ISimpleOracleStrategy.Config(10000, 50000, 100000, 100000, 3000, 3000, 10000, 10000));

        oraclePrice = 3000;
    }

    function _updatePosition(uint24 rate) private {
        uint256[] memory data = new uint256[](2);
        data[0] = oraclePrice * 10 ** 8;
        data[1] = 10 ** 8;
        vm.mockCall(
            address(datastreamOracle), 0, abi.encodeWithSelector(IOracle.getAssetsPrices.selector), abi.encode(data)
        );

        uint256 price = ((10 ** 12) << 96) / oraclePrice;
        Tick tick = TickLibrary.fromPrice(price);
        Tick tickA = Tick.wrap(Tick.unwrap(tick) - 1);
        Tick tickB = Tick.wrap(-Tick.unwrap(tick) - 1);

        vm.prank(owner);
        operator.updatePosition(key, price, tickA, tickB, rate);
    }

    function _mint(uint256 lpAmount, address user) private {
        require(user != address(this));
        uint256 amountA;
        uint256 amountB;
        uint256 supply = ERC6909Supply(address(rebalancer)).totalSupply(uint256(key));
        if (supply == 0) {
            amountA = lpAmount;
            amountB = lpAmount * oraclePrice / 10 ** 12;
        } else {
            (IRebalancer.Liquidity memory liquidityA, IRebalancer.Liquidity memory liquidityB) =
                rebalancer.getLiquidity(key);
            uint256 totalLiqauidityA = liquidityA.claimable + liquidityA.cancelable + liquidityA.reserve;
            uint256 totalLiqauidityB = liquidityB.claimable + liquidityB.cancelable + liquidityB.reserve;
            amountA = (totalLiqauidityA * lpAmount) / supply + 1;
            amountB = (totalLiqauidityB * lpAmount) / supply + 1;
        }
        ERC20PermitParams memory permitParams;
        IMinter.SwapParams memory swapParams;
        quote.approve(address(minter), amountB);
        minter.mint{value: amountA}(key, amountA, amountB, lpAmount, permitParams, permitParams, swapParams);
        ERC6909Supply(address(rebalancer)).transfer(
            user, uint256(key), ERC6909Supply(address(rebalancer)).balanceOf(address(this), uint256(key))
        );
    }

    function _take(uint256 quoteAmount) private {
        IController.TakeOrderParams[] memory orderParamsList = new IController.TakeOrderParams[](1);
        address[] memory tokensToSettle = new address[](1);
        IController.ERC20PermitParams[] memory permitParamsList;

        IBookManager.BookKey memory bookKey = IBookManager.BookKey(
            CurrencyLibrary.NATIVE,
            1,
            Currency.wrap(address(quote)),
            FeePolicyLibrary.encode(true, 0),
            IHooks(address(0)),
            FeePolicyLibrary.encode(true, 0)
        );

        orderParamsList[0] = IController.TakeOrderParams({
            id: bookKey.toId(),
            limitPrice: 0,
            quoteAmount: quoteAmount,
            maxBaseAmount: address(this).balance,
            hookData: ""
        });

        tokensToSettle[0] = address(quote);
        controller.take{value: address(this).balance}(
            orderParamsList, tokensToSettle, permitParamsList, uint64(block.timestamp)
        );
    }

    function _spend(uint256 baseAmount) private {
        IController.SpendOrderParams[] memory orderParamsList = new IController.SpendOrderParams[](1);
        address[] memory tokensToSettle = new address[](1);
        IController.ERC20PermitParams[] memory permitParamsList;

        IBookManager.BookKey memory bookKey = IBookManager.BookKey(
            Currency.wrap(address(quote)),
            1e12,
            CurrencyLibrary.NATIVE,
            FeePolicyLibrary.encode(true, 0),
            IHooks(address(0)),
            FeePolicyLibrary.encode(true, 0)
        );

        orderParamsList[0] = IController.SpendOrderParams({
            id: bookKey.toId(),
            limitPrice: 0,
            baseAmount: baseAmount,
            minQuoteAmount: 0,
            hookData: ""
        });

        tokensToSettle[0] = address(quote);
        quote.approve(address(controller), baseAmount);
        controller.spend(orderParamsList, tokensToSettle, permitParamsList, uint64(block.timestamp));
    }

    function testScenarioBullMarket() public {
        _mint(1 ether / 1000000, USER1);
        IRebalancer.Liquidity memory liquidityA;
        (liquidityA,) = rebalancer.getLiquidity(key);

        assertEq(liquidityA.reserve, 1000000000000);

        _updatePosition(1000000);
        while (true) {
            (, IRebalancer.Liquidity memory liquidityB) = rebalancer.getLiquidity(key);

            if (liquidityB.cancelable == 0) {
                break;
            }

            _take(1000);
            oraclePrice = oraclePrice + 100;
            _updatePosition(1000000);
        }
        IRebalancer.Liquidity memory liquidityB;
        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);

        assertEq(liquidityA.reserve, 1802903537555);
        assertEq(liquidityA.cancelable, 0);
        assertEq(liquidityA.claimable, 0);
        assertEq(liquidityB.reserve, 9);
        assertEq(liquidityB.cancelable, 0);
        assertEq(liquidityB.claimable, 0);

        _mint(1 ether, USER2);

        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);

        assertEq(liquidityA.reserve, 602770749389222);
        assertEq(liquidityA.cancelable, 0);
        assertEq(liquidityA.claimable, 0);
        assertEq(liquidityB.reserve, 3010);
        assertEq(liquidityB.cancelable, 0);
        assertEq(liquidityB.claimable, 0);
    }

    function testScenarioBearMarket() public {
        _mint(1 ether / 1000, USER1);
        IRebalancer.Liquidity memory liquidityB;
        (, liquidityB) = rebalancer.getLiquidity(key);

        assertEq(liquidityB.reserve, 3000000);
        _updatePosition(1000000);
        for (uint256 i = 0; i < 20; ++i) {
            (IRebalancer.Liquidity memory liquidityA,) = rebalancer.getLiquidity(key);

            _spend(100000000000000);
            oraclePrice = oraclePrice - 10;
            _updatePosition(1000000);
        }
        IRebalancer.Liquidity memory liquidityA;
        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);

        assertEq(liquidityA.reserve, 114000000000000);
        assertEq(liquidityA.cancelable, 12000000000000);
        assertEq(liquidityA.claimable, 0);
        assertEq(liquidityB.reserve, 5532763);
        assertEq(liquidityB.cancelable, 35280);
        assertEq(liquidityB.claimable, 0);

        _mint(1 ether, USER2);

        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);

        assertEq(liquidityA.reserve, 156000000000001);
        assertEq(liquidityA.cancelable, 12000000000000);
        assertEq(liquidityA.claimable, 0);
        assertEq(liquidityB.reserve, 7388778);
        assertEq(liquidityB.cancelable, 35280);
        assertEq(liquidityB.claimable, 0);
    }

    function testScenarioNormalMarket() public {
        _mint(1 ether, USER1);

        _updatePosition(1000000);

        (IRebalancer.Liquidity memory liquidityA, IRebalancer.Liquidity memory liquidityB) =
            rebalancer.getLiquidity(key);
        _spend(10000000000000000);
        _take(100000000);

        _updatePosition(1000000);
        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);

        assertEq(liquidityA.cancelable, 93333000000000000);
        assertEq(liquidityB.cancelable, 280000952);

        oraclePrice = 3200;

        _updatePosition(1000000);
        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);

        assertEq(liquidityA.cancelable, 93333000000000000);
        assertEq(liquidityB.cancelable, 298667682);

        _spend(10000000000000000);
        _take(100000000);

        oraclePrice = 3800;

        _updatePosition(1000000);
        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);

        assertEq(liquidityA.cancelable, 87125000000000000);
        assertEq(liquidityB.cancelable, 331076415);
    }

    function testScenarioLowLiquidity() public {
        _mint(1e10, USER1);
        (IRebalancer.Liquidity memory liquidityA, IRebalancer.Liquidity memory liquidityB) =
            rebalancer.getLiquidity(key);
        assertEq(liquidityA.reserve, 10000000000);
        assertEq(liquidityB.reserve, 30);

        _updatePosition(1000000);

        (liquidityA, liquidityB) = rebalancer.getLiquidity(key);

        assertEq(liquidityA.cancelable, 0);
        assertEq(liquidityB.cancelable, 3);
    }

    receive() external payable {}
}
