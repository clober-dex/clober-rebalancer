// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Tick, TickLibrary} from "clober-dex/v2-core/libraries/Tick.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {FeePolicy, FeePolicyLibrary} from "clober-dex/v2-core/libraries/FeePolicy.sol";
import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";
import {Currency} from "clober-dex/v2-core/libraries/Currency.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IOracle} from "./interfaces/IOracle.sol";

contract SimpleOracleStrategy is IStrategy, Ownable2Step {
    using FeePolicyLibrary for FeePolicy;
    using TickLibrary for Tick;

    error InvalidPrice();
    error ExceedsThreshold();

    event UpdateConfig(bytes32 indexed key, Config config);
    event UpdatePrice(bytes32 indexed key, uint256 oraclePrice, Tick tickA, Tick tickB);

    uint256 public constant RATE_PRECISION = 1e6;

    IOracle public immutable referenceOracle;
    IRebalancer public immutable rebalancer;
    IBookManager public immutable bookManager;

    struct Config {
        uint24 referenceThreshold;
        uint24 rateA;
        uint24 rateB;
        uint24 minRateA;
        uint24 minRateB;
        uint24 priceThresholdA;
        uint24 priceThresholdB;
    }

    mapping(bytes32 => Config) internal _configs;

    struct Price {
        uint208 oraclePrice;
        Tick tickA;
        Tick tickB;
    }

    mapping(bytes32 => Price) internal _prices;

    constructor(IOracle referenceOracle_, IRebalancer rebalancer_, IBookManager bookManager_, address initialOwner)
        Ownable(initialOwner)
    {
        referenceOracle = referenceOracle_;
        rebalancer = rebalancer_;
        bookManager = bookManager_;
    }

    function computeOrders(bytes32 key, uint256 amountA, uint256 amountB)
        external
        view
        returns (Order[] memory ordersA, Order[] memory ordersB)
    {
        // SimpleStrategy has only one bid and one ask order
        ordersA = new Order[](1);
        ordersB = new Order[](1);

        Config memory config = _configs[key];
        Price memory price = _prices[key];

        IBookManager.BookKey memory bookKeyA;
        IBookManager.BookKey memory bookKeyB;
        {
            (BookId bookIdA, BookId bookIdB) = rebalancer.getBookPairs(key);
            bookKeyA = bookManager.getBookKey(bookIdA);
            bookKeyB = bookManager.getBookKey(bookIdB);
        }

        (bool validity, uint256 priceA, uint256 priceB) =
            _isOraclePriceValid(price.oraclePrice, config.referenceThreshold, bookKeyA.quote, bookKeyA.base);
        if (!validity) {
            return (ordersA, ordersB);
        }

        (amountA, amountB) = _calculateAmounts(amountA, amountB, priceA, priceB, config);

        if (bookKeyA.makerPolicy.usesQuote()) amountA = bookKeyA.makerPolicy.calculateOriginalAmount(amountA, false);
        if (bookKeyB.makerPolicy.usesQuote()) amountB = bookKeyB.makerPolicy.calculateOriginalAmount(amountB, false);

        ordersA[0] = Order({tick: price.tickA, rawAmount: SafeCast.toUint64(amountA / bookKeyA.unitSize)});
        ordersB[0] = Order({tick: price.tickB, rawAmount: SafeCast.toUint64(amountB / bookKeyB.unitSize)});
    }

    function _calculateAmounts(uint256 amountA, uint256 amountB, uint256 priceA, uint256 priceB, Config memory config)
        internal
        pure
        returns (uint256 resultA, uint256 resultB)
    {
        resultA = amountA * config.rateA / RATE_PRECISION;
        resultB = amountB * config.rateB / RATE_PRECISION;

        uint256 valueA = resultA * priceA;
        uint256 valueB = resultB * priceB;

        if (valueA > valueB) {
            resultA = valueB / priceA;
            valueA = resultA * priceA;
        } else {
            resultB = valueA / priceB;
            valueB = resultB * priceB;
        }

        if (valueA < amountA * config.minRateA / RATE_PRECISION * priceA) {
            resultA = amountA * config.minRateA / RATE_PRECISION;
        }
        if (valueB < amountB * config.minRateB / RATE_PRECISION * priceB) {
            resultB = amountB * config.minRateB / RATE_PRECISION;
        }
    }

    function isOraclePriceValid(bytes32 key) external view returns (bool) {
        Config memory config = _configs[key];
        Price memory price = _prices[key];

        (BookId bookIdA,) = rebalancer.getBookPairs(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);

        (bool validity,,) =
            _isOraclePriceValid(price.oraclePrice, config.referenceThreshold, bookKeyA.quote, bookKeyA.base);
        return validity;
    }

    function _isOraclePriceValid(
        uint256 oraclePrice,
        uint256 referenceThreshold,
        Currency currencyA,
        Currency currencyB
    ) internal view returns (bool, uint256 priceA, uint256 priceB) {
        uint256 referencePrice;
        address[] memory assets = new address[](2);
        assets[0] = Currency.unwrap(currencyA);
        assets[1] = Currency.unwrap(currencyB);

        try referenceOracle.getAssetsPrices(assets) returns (uint256[] memory prices) {
            // price = basePrice / quotePrice
            referencePrice = prices[1] * 10 ** referenceOracle.decimals() / prices[0];
            priceA = prices[0];
            priceB = prices[1];
        } catch {
            return (false, 0, 0);
        }

        if (
            referencePrice * (RATE_PRECISION + referenceThreshold) / RATE_PRECISION < oraclePrice
                || referencePrice * (RATE_PRECISION - referenceThreshold) / RATE_PRECISION > oraclePrice
        ) {
            return (false, 0, 0);
        }
        return (true, priceA, priceB);
    }

    function updatePrice(bytes32 key, uint256 oraclePrice, Tick tickA, Tick tickB) external onlyOwner {
        uint256 priceA = tickA.toPrice();
        uint256 priceB = Tick.wrap(-Tick.unwrap(tickB)).toPrice();

        if (priceA >= priceB) revert InvalidPrice();

        Config memory config = _configs[key];
        if (
            oraclePrice * (RATE_PRECISION + config.priceThresholdA) / RATE_PRECISION < priceA
                || oraclePrice * (RATE_PRECISION - config.priceThresholdA) / RATE_PRECISION > priceA
                || oraclePrice * (RATE_PRECISION + config.priceThresholdB) / RATE_PRECISION < priceB
                || oraclePrice * (RATE_PRECISION - config.priceThresholdB) / RATE_PRECISION > priceB
        ) revert ExceedsThreshold();

        (BookId bookIdA,) = rebalancer.getBookPairs(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        uint8 decimalsA = IERC20Metadata(Currency.unwrap(bookKeyA.quote)).decimals();
        uint8 decimalsB = IERC20Metadata(Currency.unwrap(bookKeyA.base)).decimals();

        // @dev Convert oracle price to the same decimals as the reference oracle
        oraclePrice = oraclePrice * 10 ** decimalsB / 10 ** decimalsA;
        oraclePrice = (oraclePrice * 10 ** referenceOracle.decimals()) >> 96;

        _prices[key] = Price({oraclePrice: SafeCast.toUint208(oraclePrice), tickA: tickA, tickB: tickB});
        emit UpdatePrice(key, oraclePrice, tickA, tickB);
    }

    function setConfig(bytes32 key, Config memory config) external onlyOwner {
        _configs[key] = config;
        emit UpdateConfig(key, config);
    }
}
