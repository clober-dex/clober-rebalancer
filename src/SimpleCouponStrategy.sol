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

    IBookManager public immutable bookManager;
    uint256 public constant PRECISION = 1 << 96;

    struct CouponStrategy {
        Epoch epoch;
        uint96 bidRate;
        uint96 askRate;
    }

    mapping(bytes32 key => CouponStrategy) private _strategy;

    constructor(IBookManager bookManager_, address initialOwner_) Ownable(initialOwner_) {
        bookManager = bookManager_;
    }

    function calculateCouponPrice(Epoch epoch, uint96 ratePerSecond) public view returns (uint256 price) {
        Epoch current = EpochLibrary.current();
        if (current > epoch) {
            return 0;
        }
        uint256 thisTimestamp = block.timestamp;
        price = FixedPointMathLib.rpow(PRECISION + ratePerSecond, epoch.endTime() - thisTimestamp, PRECISION);
        if (epoch > current) {
            price -=
                FixedPointMathLib.rpow(PRECISION + ratePerSecond, epoch.sub(1).endTime() - thisTimestamp, PRECISION);
        } else {
            price -= PRECISION;
        }
    }

    function calculateCouponTick(BookId bookIdA, BookId bookIdB) public view returns (Tick bidTick, Tick askTick) {
        bytes32 key = encodeKey(bookIdA, bookIdB);
        CouponStrategy memory strategy = _strategy[key];
        bidTick = TickLibrary.fromPrice(calculateCouponPrice(strategy.epoch, strategy.bidRate) * 2 ** 32);
        askTick = Tick.wrap(
            -Tick.unwrap(TickLibrary.fromPrice(calculateCouponPrice(strategy.epoch, strategy.askRate) * 2 ** 32))
        );
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
            Liquidity({tick: bidTick, rawAmount: SafeCast.toUint64(amountA / bookManager.getBookKey(bookIdA).unit)});
        asks[0] =
            Liquidity({tick: askTick, rawAmount: SafeCast.toUint64(amountB / bookManager.getBookKey(bookIdB).unit)});
    }

    function setCouponStrategy(BookId bookIdA, BookId bookIdB, Epoch epoch, uint96 bidRate, uint96 askRate)
        external
        onlyOwner
    {
        bytes32 key = encodeKey(bookIdA, bookIdB);
        _strategy[key] = CouponStrategy({epoch: epoch, bidRate: bidRate, askRate: askRate});
    }

    function getCouponStrategy(BookId bookIdA, BookId bookIdB) external view returns (CouponStrategy memory) {
        return _strategy[encodeKey(bookIdA, bookIdB)];
    }

    function encodeKey(BookId bookIdA, BookId bookIdB) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(bookIdA, bookIdB));
    }
}
