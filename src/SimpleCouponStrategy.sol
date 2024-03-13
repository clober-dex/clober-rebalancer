// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {Tick, TickLibrary} from "clober-dex/v2-core/libraries/Tick.sol";
import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {Epoch, EpochLibrary} from "./libraries/Epoch.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";

contract SimpleCouponStrategy is IStrategy, Ownable2Step {
    using TickLibrary for Tick;
    using EpochLibrary for Epoch;

    IBookManager private immutable _bookManager;
    uint256 private constant _PRECISION = 1e18;

    struct CouponStrategy {
        Epoch epoch;
        uint64 bidRate;
        uint64 askRate;
    }

    mapping(bytes32 key => CouponStrategy) private _strategy;

    constructor(IBookManager bookManager_, address initialOwner_) Ownable(initialOwner_) {
        _bookManager = bookManager_;
    }

    function calculateCouponPrice(Epoch epoch, uint256 ratePerSecond) public view returns (uint256 price) {
        Epoch current = EpochLibrary.current();
        if (current > epoch) {
            return 0;
        }
        uint256 thisTimestamp = block.timestamp;
        price = FixedPointMathLib.rpow(_PRECISION + ratePerSecond, epoch.endTime() - thisTimestamp, _PRECISION);
        if (epoch > current) {
            price -= FixedPointMathLib.rpow(_PRECISION + ratePerSecond, epoch.sub(1).endTime() - thisTimestamp, _PRECISION);
        } else {
            price -= _PRECISION;
        }
    }

    function calculateCouponTick(BookId bookIdA, BookId bookIdB) public view returns (Tick bidTick, Tick askTick) {
        bytes32 key = _encodeKey(bookIdA, bookIdB);
        CouponStrategy memory strategy = _strategy[key];
        bidTick = TickLibrary.fromPrice(calculateCouponPrice(strategy.epoch, strategy.bidRate));
        askTick = Tick.wrap(-Tick.unwrap(TickLibrary.fromPrice(calculateCouponPrice(strategy.epoch, strategy.askRate))));
    }

    function computeAllocation(BookId bookIdA, uint256 amountA, BookId bookIdB, uint256 amountB)
        external
        view
        returns (Liquidity[] memory bids, Liquidity[] memory asks)
    {
        bids = new Liquidity[](1);
        asks = new Liquidity[](1);

        (Tick bidTick, Tick askTick) = calculateCouponTick(bookIdA, bookIdB);

        bids[0] =
            Liquidity({tick: bidTick, rawAmount: SafeCast.toUint64(amountA / _bookManager.getBookKey(bookIdA).unit)});
        asks[0] =
            Liquidity({tick: askTick, rawAmount: SafeCast.toUint64(amountB / _bookManager.getBookKey(bookIdB).unit)});
    }

    function setCouponStrategy(BookId bookIdA, BookId bookIdB, Epoch epoch, uint64 bidRate, uint64 askRate)
        external
        onlyOwner
    {
        bytes32 key = _encodeKey(bookIdA, bookIdB);
        _strategy[key] = CouponStrategy({epoch: epoch, bidRate: bidRate, askRate: askRate});
    }

    function getCouponStrategy(BookId bookIdA, BookId bookIdB) external view returns (CouponStrategy memory) {
        return _strategy[_encodeKey(bookIdA, bookIdB)];
    }

    function _encodeKey(BookId bookIdA, BookId bookIdB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bookIdA, bookIdB));
    }
}
