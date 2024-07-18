// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {FeePolicy, FeePolicyLibrary} from "clober-dex/v2-core/libraries/FeePolicy.sol";
import {Tick, TickLibrary} from "clober-dex/v2-core/libraries/Tick.sol";
import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Epoch, EpochLibrary} from "./external/coupon-finance/Epoch.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IPoolStorage} from "./interfaces/IPoolStorage.sol";

contract SimpleCouponStrategy is IStrategy, Ownable2Step {
    using FeePolicyLibrary for FeePolicy;
    using TickLibrary for Tick;
    using EpochLibrary for Epoch;

    IPoolStorage public immutable poolStorage;
    IBookManager public immutable bookManager;
    uint256 public constant PRECISION = 1 << 96;

    struct CouponStrategy {
        Epoch epoch;
        uint96 bidRate;
        uint96 askRate;
    }

    mapping(bytes32 key => CouponStrategy) private _strategy;

    constructor(IPoolStorage poolStorage_, IBookManager bookManager_, address initialOwner_) Ownable(initialOwner_) {
        poolStorage = poolStorage_;
        bookManager = bookManager_;
    }

    function calculateCouponPrice(Epoch epoch, uint96 ratePerSecond) public view returns (uint256 price) {
        Epoch current = EpochLibrary.current();
        if (current > epoch) return 0;
        uint256 thisTimestamp = block.timestamp;
        price = FixedPointMathLib.rpow(PRECISION + ratePerSecond, epoch.endTime() - thisTimestamp, PRECISION);
        if (epoch > current) {
            price -=
                FixedPointMathLib.rpow(PRECISION + ratePerSecond, epoch.sub(1).endTime() - thisTimestamp, PRECISION);
        } else {
            price -= PRECISION;
        }
    }

    function calculateCouponTick(bytes32 key) public view returns (Tick bidTick, Tick askTick) {
        CouponStrategy memory strategy = _strategy[key];
        bidTick = TickLibrary.fromPrice(calculateCouponPrice(strategy.epoch, strategy.bidRate));
        askTick = Tick.wrap(-Tick.unwrap(TickLibrary.fromPrice(calculateCouponPrice(strategy.epoch, strategy.askRate))));
    }

    function computeOrders(bytes32 key, uint256 amountA, uint256 amountB)
        external
        view
        returns (Order[] memory bids, Order[] memory asks)
    {
        bids = new Order[](1);
        asks = new Order[](1);

        (BookId bookIdA, BookId bookIdB) = poolStorage.getBookPairs(key);
        (Tick bidTick, Tick askTick) = calculateCouponTick(key);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(bookIdB);

        if (bookKeyA.makerPolicy.usesQuote()) amountA = bookKeyA.makerPolicy.calculateOriginalAmount(amountA, false);
        if (bookKeyB.makerPolicy.usesQuote()) amountB = bookKeyB.makerPolicy.calculateOriginalAmount(amountB, false);

        bids[0] = Order({tick: bidTick, rawAmount: SafeCast.toUint64(amountA / bookKeyA.unitSize)});
        asks[0] = Order({tick: askTick, rawAmount: SafeCast.toUint64(amountB / bookKeyB.unitSize)});
    }

    function setCouponStrategy(bytes32 key, Epoch epoch, uint96 bidRate, uint96 askRate) external onlyOwner {
        _strategy[key] = CouponStrategy({epoch: epoch, bidRate: bidRate, askRate: askRate});
    }

    function getCouponStrategy(bytes32 key) external view returns (CouponStrategy memory) {
        return _strategy[key];
    }
}
