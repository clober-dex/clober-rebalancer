// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Tick, TickLibrary} from "clober-dex/v2-core/libraries/Tick.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {FeePolicy, FeePolicyLibrary} from "clober-dex/v2-core/libraries/FeePolicy.sol";
import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IRebalancer} from "./interfaces/IRebalancer.sol";

contract SimpleOracleStrategy is IStrategy, Ownable2Step {
    using FeePolicyLibrary for FeePolicy;
    using TickLibrary for Tick;

    error InvalidPrice();

    struct Config {
        uint256 referenceThreshold;
        uint24 rateA;
        uint24 rateB;
        uint24 priceThresholdA;
        uint24 priceThresholdB;
    }

    struct Price {
        uint208 price;
        Tick tickA;
        Tick tickB;
    }

    uint256 public constant RATE_PRECISION = 1e6;

    IRebalancer public immutable rebalancer;
    IBookManager public immutable bookManager;

    mapping(bytes32 => Config) internal _configs;
    mapping(bytes32 => Price) internal _prices;

    constructor(IRebalancer rebalancer_, IBookManager bookManager_, address initialOwner) Ownable(initialOwner) {
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

        if (_isOraclePriceValid()) {
            return (ordersA, ordersB);
        }

        (BookId bookIdA, BookId bookIdB) = rebalancer.getBookPairs(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(bookIdB);

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

    function _isOraclePriceValid() internal view returns (bool) {
        // TODO: check if reference price is valid
        // TODO: check if oracle price is out of range
        return true;
    }

    function updatePrice(bytes32 key, uint208 oraclePrice, Tick tickA, Tick tickB) external onlyOwner {
        uint256 priceA = tickA.toPrice();
        uint256 priceB = Tick.wrap(-Tick.unwrap(tickB)).toPrice();

        if (priceA >= priceB) revert InvalidPrice();

        Config memory config = _configs[key];
        if (
            uint256(oraclePrice) * (RATE_PRECISION + config.priceThresholdA) / RATE_PRECISION < priceA
                || uint256(oraclePrice) * (RATE_PRECISION - config.priceThresholdA) / RATE_PRECISION > priceA
                || uint256(oraclePrice) * (RATE_PRECISION + config.priceThresholdB) / RATE_PRECISION < priceB
                || uint256(oraclePrice) * (RATE_PRECISION - config.priceThresholdB) / RATE_PRECISION > priceB
        ) revert InvalidPrice();

        _prices[key] = Price({price: oraclePrice, tickA: tickA, tickB: tickB});
        // todo emit event
    }

    // todo: add setConfig function
}
