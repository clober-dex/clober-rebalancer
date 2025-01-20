// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
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
    uint256 public constant LAST_RAW_AMOUNT_MASK = (1 << 128) - 1;

    IOracle public immutable referenceOracle;
    IRebalancer public immutable rebalancer;
    IBookManager public immutable bookManager;

    mapping(address => bool) public isOperator;
    mapping(bytes32 => Config) internal _configs;
    mapping(bytes32 => Position) internal _positions;
    mapping(bytes32 => uint256) internal _lastAmountA;
    mapping(bytes32 => uint256) internal _lastAmountB;

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

    function getPosition(bytes32 key) external view returns (Position memory) {
        return _positions[key];
    }

    function getLastAmount(bytes32 key) external view returns (uint256, uint256) {
        return (_lastAmountA[key], _lastAmountB[key]);
    }

    function computeOrders(bytes32 key) external view returns (Order[] memory ordersA, Order[] memory ordersB) {
        Position memory position = _positions[key];
        if (position.paused) revert Paused();

        Config memory config = _configs[key];

        IBookManager.BookKey memory bookKeyA;
        IBookManager.BookKey memory bookKeyB;
        IRebalancer.Liquidity memory liquidityA;
        IRebalancer.Liquidity memory liquidityB;
        {
            (BookId bookIdA, BookId bookIdB) = rebalancer.getBookPairs(key);
            bookKeyA = bookManager.getBookKey(bookIdA);
            bookKeyB = bookManager.getBookKey(bookIdB);

            (liquidityA, liquidityB) = rebalancer.getLiquidity(key);

            if (
                (_lastAmountA[key] > 0 || _lastAmountB[key] > 0)
                    && (
                        liquidityA.cancelable > _lastAmountA[key] * config.rebalanceThreshold / RATE_PRECISION
                            || liquidityB.cancelable > _lastAmountB[key] * config.rebalanceThreshold / RATE_PRECISION
                    )
            ) {
                return (ordersA, ordersB);
            }

            if (!_isOraclePriceValid(position.oraclePrice, config.referenceThreshold, bookKeyA.quote, bookKeyA.base)) {
                revert InvalidOraclePrice();
            }
        }

        (uint256 amountA, uint256 amountB) = _calculateAmounts(
            liquidityA.reserve + liquidityA.cancelable + liquidityA.claimable,
            liquidityB.reserve + liquidityB.cancelable + liquidityB.claimable,
            position.oraclePrice,
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
            tick: position.tickA,
            rawAmount: SafeCast.toUint64(amountA * position.rate / bookKeyA.unitSize / RATE_PRECISION)
        });
        ordersB[0] = Order({
            tick: position.tickB,
            rawAmount: SafeCast.toUint64(amountB * position.rate / bookKeyB.unitSize / RATE_PRECISION)
        });

        return (ordersA, ordersB);
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
        Position memory position = _positions[key];

        (BookId bookIdA,) = rebalancer.getBookPairs(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);

        return _isOraclePriceValid(position.oraclePrice, config.referenceThreshold, bookKeyA.quote, bookKeyA.base);
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

    function isPaused(bytes32 key) external view returns (bool) {
        return _positions[key].paused;
    }

    function pause(bytes32 key) external onlyOperator {
        delete _lastAmountA[key];
        delete _lastAmountB[key];
        _positions[key].paused = true;
        emit Pause(key);
    }

    function unpause(bytes32 key) external onlyOperator {
        _positions[key].paused = false;
        emit Unpause(key);
    }

    function updatePosition(bytes32 key, uint256 oraclePrice, Tick tickA, Tick tickB, uint24 rate)
        external
        onlyOperator
    {
        if (rate > RATE_PRECISION) revert InvalidValue();

        uint256 priceA = tickA.toPrice();
        uint256 priceB = Tick.wrap(-Tick.unwrap(tickB)).toPrice();

        Config memory config = _configs[key];
        if (
            oraclePrice < TickLibrary.MIN_PRICE || oraclePrice > TickLibrary.MAX_PRICE
                || oraclePrice * (RATE_PRECISION + config.priceThresholdA) / RATE_PRECISION < priceA
                || oraclePrice * (RATE_PRECISION - config.priceThresholdB) / RATE_PRECISION > priceB
        ) revert ExceedsThreshold();

        (BookId bookIdA, BookId bookIdB) = rebalancer.getBookPairs(key);
        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        priceA = bookKeyA.makerPolicy.usesQuote()
            ? uint256(int256(priceA) + bookKeyA.makerPolicy.calculateFee(priceA, false))
            : bookKeyA.makerPolicy.calculateOriginalAmount(priceA, true);

        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(bookIdB);
        priceB = bookKeyB.makerPolicy.usesQuote()
            ? bookKeyB.makerPolicy.calculateOriginalAmount(priceB, false)
            : uint256(int256(priceB) - bookKeyB.makerPolicy.calculateFee(priceB, false));

        if (priceA >= priceB) revert InvalidPrice();

        // @dev Convert oracle price to the same decimals as the reference oracle
        oraclePrice =
            oraclePrice * 10 ** _getCurrencyDecimals(bookKeyA.base) / 10 ** _getCurrencyDecimals(bookKeyA.quote);
        oraclePrice = Math.mulDiv(oraclePrice, 10 ** referenceOracle.decimals(), 1 << 96);
        if (!_isOraclePriceValid(oraclePrice, config.referenceThreshold, bookKeyA.quote, bookKeyA.base)) {
            revert InvalidOraclePrice();
        }

        Position memory position = _positions[key];
        position.oraclePrice = SafeCast.toUint176(oraclePrice);
        position.tickA = tickA;
        position.tickB = tickB;
        position.rate = rate;

        _positions[key] = position;
        delete _lastAmountA[key];
        delete _lastAmountB[key];
        emit UpdatePosition(key, oraclePrice, tickA, tickB, rate);
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

    function mintHook(address, bytes32, uint256, uint256) external view {
        if (msg.sender != address(rebalancer)) revert InvalidAccess();
    }

    function burnHook(address, bytes32 key, uint256 burnAmount, uint256 lastTotalSupply) external {
        if (msg.sender != address(rebalancer)) revert InvalidAccess();
        _lastAmountA[key] -= _lastAmountA[key] * burnAmount / lastTotalSupply;
        _lastAmountB[key] -= _lastAmountB[key] * burnAmount / lastTotalSupply;
    }

    function rebalanceHook(address, bytes32 key, Order[] memory, Order[] memory, uint256 amountA, uint256 amountB)
        external
    {
        if (msg.sender != address(rebalancer)) revert InvalidAccess();
        _lastAmountA[key] = amountA;
        _lastAmountB[key] = amountB;
    }
}
