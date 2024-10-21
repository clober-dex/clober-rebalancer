// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Tick, TickLibrary} from "clober-dex/v2-core/libraries/Tick.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {FeePolicy, FeePolicyLibrary} from "clober-dex/v2-core/libraries/FeePolicy.sol";
import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";
import {Currency, CurrencyLibrary} from "clober-dex/v2-core/libraries/Currency.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {ISimpleOracleStrategy} from "./interfaces/ISimpleOracleStrategy.sol";
import {IRebalancer} from "./interfaces/IRebalancer.sol";

contract SimpleOracleStrategy is ISimpleOracleStrategy, Ownable2Step {
    using CurrencyLibrary for Currency;
    using FeePolicyLibrary for FeePolicy;
    using TickLibrary for Tick;

    uint256 public constant RATE_PRECISION = 1e6;
    uint256 public constant LAST_RAW_AMOUNT_MASK = 1 << 128 - 1;

    IOracle public immutable referenceOracle;
    IRebalancer public immutable rebalancer;
    IBookManager public immutable bookManager;

    mapping(address => bool) public isOperator;
    mapping(bytes32 => Config) internal _configs;
    mapping(bytes32 => Price) internal _prices;
    mapping(bytes32 => uint256) internal _lastRawAmounts;

    uint256 internal _alpha;

    modifier onlyOperator() {
        if (!isOperator[msg.sender]) revert NotOperator();
        _;
    }

    constructor(IOracle referenceOracle_, IRebalancer rebalancer_, IBookManager bookManager_, address initialOwner)
        Ownable(initialOwner)
    {
        referenceOracle = referenceOracle_;
        rebalancer = rebalancer_;
        bookManager = bookManager_;
    }

    function getConfig(bytes32 key) external view returns (Config memory) {
        return _configs[key];
    }

    function getPrice(bytes32 key) external view returns (Price memory) {
        return _prices[key];
    }

    function getAlpha() external view returns (uint256) {
        return _alpha;
    }

    function getLastRawAmount(bytes32 key) external view returns (uint256, uint256) {
        uint256 lastRawAmounts = _lastRawAmounts[key];
        return (lastRawAmounts >> 128, lastRawAmounts & LAST_RAW_AMOUNT_MASK);
    }

    function computeOrders(bytes32 key) external view returns (Order[] memory ordersA, Order[] memory ordersB) {
        Config memory config = _configs[key];
        Price memory price = _prices[key];

        IBookManager.BookKey memory bookKeyA;
        IBookManager.BookKey memory bookKeyB;
        IRebalancer.Liquidity memory liquidityA;
        IRebalancer.Liquidity memory liquidityB;
        {
            (BookId bookIdA, BookId bookIdB) = rebalancer.getBookPairs(key);
            bookKeyA = bookManager.getBookKey(bookIdA);
            bookKeyB = bookManager.getBookKey(bookIdB);

            (IRebalancer.Liquidity memory liquidityA, IRebalancer.Liquidity memory liquidityB) =
                rebalancer.getLiquidity(key);

            uint256 lastRawAmounts = _lastRawAmounts[key];
            if (
                liquidityA.cancelable
                    > (lastRawAmounts >> 128) * bookKeyA.unitSize * config.rebalanceThreshold / RATE_PRECISION
                    || liquidityB.cancelable
                        > (lastRawAmounts & LAST_RAW_AMOUNT_MASK) * bookKeyB.unitSize * config.rebalanceThreshold
                            / RATE_PRECISION
            ) {
                return (ordersA, ordersB);
            }
        }

        if (!_isOraclePriceValid(price.oraclePrice, config.referenceThreshold, bookKeyA.quote, bookKeyA.base)) {
            return (ordersA, ordersB);
        }

        (uint256 amountA, uint256 amountB) = _calculateAmounts(
            liquidityA.reserve + liquidityA.cancelable + liquidityA.claimable,
            liquidityB.reserve + liquidityB.cancelable + liquidityB.claimable,
            price.oraclePrice,
            _getCurrencyDecimals(bookKeyA.quote),
            _getCurrencyDecimals(bookKeyA.base),
            config
        );

        if (bookKeyA.makerPolicy.usesQuote()) amountA = bookKeyA.makerPolicy.calculateOriginalAmount(amountA, false);
        if (bookKeyB.makerPolicy.usesQuote()) amountB = bookKeyB.makerPolicy.calculateOriginalAmount(amountB, false);

        // SimpleStrategy has only one bid and one ask order
        ordersA = new Order[](1);
        ordersB = new Order[](1);
        ordersA[0] = Order({
            tick: price.tickA,
            rawAmount: SafeCast.toUint64(amountA * _alpha / bookKeyA.unitSize / RATE_PRECISION)
        });
        ordersB[0] = Order({
            tick: price.tickB,
            rawAmount: SafeCast.toUint64(amountB * _alpha / bookKeyB.unitSize / RATE_PRECISION)
        });
    }

    function _calculateAmounts(
        uint256 amountA,
        uint256 amountB,
        uint256 oraclePrice,
        uint8 decimalsA,
        uint8 decimalsB,
        Config memory config
    ) internal view returns (uint256 resultA, uint256 resultB) {
        // @dev Use the same decimals for both amounts to calculate the value properly
        if (decimalsA > decimalsB) {
            amountB = amountB * 10 ** (decimalsA - decimalsB);
        } else if (decimalsA < decimalsB) {
            amountA = amountA * 10 ** (decimalsB - decimalsA);
        }

        resultA = amountA * config.rateA / RATE_PRECISION;
        resultB = amountB * config.rateB / RATE_PRECISION;

        uint256 basePrice = 10 ** referenceOracle.decimals();
        uint256 valueA = resultA * basePrice;
        uint256 valueB = resultB * oraclePrice;

        if (valueA > valueB) {
            resultA = valueB / basePrice;
            valueA = resultA * basePrice;
        } else {
            resultB = valueA / oraclePrice;
            valueB = resultB * oraclePrice;
        }

        if (valueA < amountA * config.minRateA / RATE_PRECISION * basePrice) {
            resultA = amountA * config.minRateA / RATE_PRECISION;
        }
        if (valueB < amountB * config.minRateB / RATE_PRECISION * oraclePrice) {
            resultB = amountB * config.minRateB / RATE_PRECISION;
        }

        // @dev Turn back to original decimals
        if (decimalsA > decimalsB) {
            resultB = resultB / 10 ** (decimalsA - decimalsB);
        } else if (decimalsA < decimalsB) {
            resultA = resultA / 10 ** (decimalsB - decimalsA);
        }
    }

    function isOraclePriceValid(bytes32 key) external view returns (bool) {
        Config memory config = _configs[key];
        Price memory price = _prices[key];

        (BookId bookIdA,) = rebalancer.getBookPairs(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);

        return _isOraclePriceValid(price.oraclePrice, config.referenceThreshold, bookKeyA.quote, bookKeyA.base);
    }

    function _isOraclePriceValid(
        uint256 oraclePrice,
        uint256 referenceThreshold,
        Currency currencyA,
        Currency currencyB
    ) internal view returns (bool) {
        uint256 referencePrice;
        address[] memory assets = new address[](2);
        assets[0] = Currency.unwrap(currencyA);
        assets[1] = Currency.unwrap(currencyB);

        try referenceOracle.getAssetsPrices(assets) returns (uint256[] memory prices) {
            // price = basePrice / quotePrice
            referencePrice = prices[1] * 10 ** referenceOracle.decimals() / prices[0];
        } catch {
            return false;
        }

        if (
            referencePrice * (RATE_PRECISION + referenceThreshold) / RATE_PRECISION < oraclePrice
                || referencePrice * (RATE_PRECISION - referenceThreshold) / RATE_PRECISION > oraclePrice
        ) {
            return false;
        }
        return true;
    }

    function updatePrice(bytes32 key, uint256 oraclePrice, Tick tickA, Tick tickB, uint256 alpha)
        external
        onlyOperator
    {
        uint256 priceA = tickA.toPrice();
        uint256 priceB = Tick.wrap(-Tick.unwrap(tickB)).toPrice();

        if (priceA >= priceB) revert InvalidPrice();
        if (alpha > RATE_PRECISION) revert InvalidValue();
        if (alpha > 0) _alpha = alpha;

        Config memory config = _configs[key];
        if (
            oraclePrice * (RATE_PRECISION + config.priceThresholdA) / RATE_PRECISION < priceA
                || oraclePrice * (RATE_PRECISION - config.priceThresholdA) / RATE_PRECISION > priceA
                || oraclePrice * (RATE_PRECISION + config.priceThresholdB) / RATE_PRECISION < priceB
                || oraclePrice * (RATE_PRECISION - config.priceThresholdB) / RATE_PRECISION > priceB
        ) revert ExceedsThreshold();

        (BookId bookIdA,) = rebalancer.getBookPairs(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        uint8 decimalsA = _getCurrencyDecimals(bookKeyA.quote);
        uint8 decimalsB = _getCurrencyDecimals(bookKeyA.base);

        // @dev Convert oracle price to the same decimals as the reference oracle
        oraclePrice = oraclePrice * 10 ** decimalsB / 10 ** decimalsA;
        oraclePrice = (oraclePrice * 10 ** referenceOracle.decimals()) >> 96;

        _prices[key] = Price({oraclePrice: SafeCast.toUint208(oraclePrice), tickA: tickA, tickB: tickB});
        emit UpdatePrice(key, oraclePrice, tickA, tickB, alpha > 0 ? alpha : _alpha);
    }

    function setConfig(bytes32 key, Config memory config) external onlyOwner {
        if (
            config.referenceThreshold > RATE_PRECISION || config.rebalanceThreshold > RATE_PRECISION
                || config.rateA > RATE_PRECISION || config.rateB > RATE_PRECISION || config.minRateA > RATE_PRECISION
                || config.minRateB > RATE_PRECISION || config.priceThresholdA > RATE_PRECISION
                || config.priceThresholdB > RATE_PRECISION
        ) revert InvalidConfig();

        if (config.rateA < config.minRateA || config.rateB < config.minRateB) revert InvalidConfig();

        _configs[key] = config;
        emit UpdateConfig(key, config);
    }

    function setOperator(address operator, bool status) external onlyOwner {
        isOperator[operator] = status;
        emit SetOperator(operator, status);
    }

    function _getCurrencyDecimals(Currency currency) internal view returns (uint8) {
        return currency.isNative() ? 18 : IERC20Metadata(Currency.unwrap(currency)).decimals();
    }

    function mintHook(address sender, bytes32 key, uint256 mintAmount, uint256 totalSupply) external view {
        if (msg.sender != address(rebalancer)) revert InvalidAccess();
    }

    function burnHook(address sender, bytes32 key, uint256 burnAmount, uint256 totalSupply) external {
        if (msg.sender != address(rebalancer)) revert InvalidAccess();
        uint256 lastRawAmounts = _lastRawAmounts[key];
        _lastRawAmounts[key] = lastRawAmounts - ((lastRawAmounts >> 128) * burnAmount / totalSupply)
            << 128 - (lastRawAmounts & LAST_RAW_AMOUNT_MASK) * burnAmount / totalSupply;
    }

    function rebalanceHook(address sender, bytes32 key, Order[] memory liquidityA, Order[] memory liquidityB)
        external
    {
        if (msg.sender != address(rebalancer)) revert InvalidAccess();
        uint256 lastRawAmountA;
        uint256 lastRawAmountB;
        for (uint256 i = 0; i < liquidityA.length; ++i) {
            IStrategy.Order memory order = liquidityA[i];
            lastRawAmountA += order.rawAmount;
        }

        for (uint256 i = 0; i < liquidityB.length; ++i) {
            IStrategy.Order memory order = liquidityB[i];
            lastRawAmountB += order.rawAmount;
        }
        _lastRawAmounts[key] = lastRawAmountA << 128 + lastRawAmountB;
    }
}
