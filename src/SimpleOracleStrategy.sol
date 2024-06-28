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

        (BookId bookIdA, BookId bookIdB) = rebalancer.getBookPairs(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(bookIdB);

        if (_isOraclePriceValid(price.oraclePrice, config.referenceThreshold, bookKeyA.quote, bookKeyA.base)) {
            return (ordersA, ordersB);
        }

        if (bookKeyA.makerPolicy.usesQuote()) amountA = bookKeyA.makerPolicy.calculateOriginalAmount(amountA, false);
        if (bookKeyB.makerPolicy.usesQuote()) amountB = bookKeyB.makerPolicy.calculateOriginalAmount(amountB, false);

        ordersA[0] = Order({
            tick: price.tickA,
            rawAmount: SafeCast.toUint64(amountA * config.rateA / RATE_PRECISION / bookKeyA.unitSize)
        });
        ordersB[0] = Order({
            tick: price.tickB,
            rawAmount: SafeCast.toUint64(amountB * config.rateB / RATE_PRECISION / bookKeyB.unitSize)
        });
    }

    function isOraclePriceValid(bytes32 key) external view returns (bool) {
        Config memory config = _configs[key];
        Price memory price = _prices[key];

        (BookId bookIdA,) = rebalancer.getBookPairs(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);

        return _isOraclePriceValid(price.oraclePrice, config.referenceThreshold, bookKeyA.quote, bookKeyA.base);
    }

    function _isOraclePriceValid(uint256 oraclePrice, uint256 referenceThreshold, Currency quote, Currency base)
        internal
        view
        returns (bool)
    {
        uint256 referencePrice;
        address[] memory assets = new address[](2);
        assets[0] = Currency.unwrap(quote);
        assets[1] = Currency.unwrap(base);

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
        ) revert InvalidPrice();

        (BookId bookIdA,) = rebalancer.getBookPairs(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        uint8 quoteDecimals = IERC20Metadata(Currency.unwrap(bookKeyA.quote)).decimals();
        uint8 baseDecimals = IERC20Metadata(Currency.unwrap(bookKeyA.base)).decimals();

        // @dev Convert oracle price to the same decimals as the reference oracle
        oraclePrice = oraclePrice * 10 ** quoteDecimals / 10 ** baseDecimals;
        oraclePrice = (oraclePrice * 10 ** referenceOracle.decimals()) >> 96;

        _prices[key] = Price({oraclePrice: SafeCast.toUint208(oraclePrice), tickA: tickA, tickB: tickB});
        emit UpdatePrice(key, oraclePrice, tickA, tickB);
    }

    function setConfig(bytes32 key, Config memory config) external onlyOwner {
        _configs[key] = config;
        emit UpdateConfig(key, config);
    }
}
