// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {ILocker} from "clober-dex/v2-core/interfaces/ILocker.sol";
import {BookId, BookIdLibrary} from "clober-dex/v2-core/libraries/BookId.sol";
import {Currency, CurrencyLibrary} from "clober-dex/v2-core/libraries/Currency.sol";
import {OrderId, OrderIdLibrary} from "clober-dex/v2-core/libraries/OrderId.sol";
import {Tick, TickLibrary} from "clober-dex/v2-core/libraries/Tick.sol";
import {FeePolicy, FeePolicyLibrary} from "clober-dex/v2-core/libraries/FeePolicy.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {ERC6909Supply} from "./libraries/ERC6909Supply.sol";

contract Rebalancer is IRebalancer, ILocker, Ownable2Step, ERC6909Supply {
    using BookIdLibrary for IBookManager.BookKey;
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using OrderIdLibrary for OrderId;
    using TickLibrary for Tick;
    using FeePolicyLibrary for FeePolicy;

    IBookManager public immutable bookManager;

    mapping(bytes32 key => Pool) private _pools;
    mapping(BookId => BookId) public bookPair;

    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    constructor(IBookManager bookManager_, address initialOwner_) Ownable(initialOwner_) {
        bookManager = bookManager_;
    }

    function getPool(bytes32 key) external view returns (Pool memory) {
        return _pools[key];
    }

    function getBookPairs(bytes32 key) external view returns (BookId, BookId) {
        Pool storage pool = _pools[key];
        return (pool.bookIdA, pool.bookIdB);
    }

    function getLiquidity(bytes32 key) public view returns (uint256 liquidityA, uint256 liquidityB) {
        Pool storage pool = _pools[key];
        liquidityA = pool.reserveA;
        liquidityB = pool.reserveB;

        OrderId[] memory orderListA = pool.orderListA;
        OrderId[] memory orderListB = pool.orderListB;

        if (orderListA.length > 0) {
            IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(pool.bookIdA);
            for (uint256 i; i < orderListA.length; ++i) {
                (uint256 cancelable, uint256 claimable) = _getLiquidity(bookKeyA, orderListA[i]);
                liquidityA += cancelable;
                liquidityB += claimable;
            }
        }
        if (orderListB.length > 0) {
            IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(pool.bookIdB);
            for (uint256 i; i < orderListB.length; ++i) {
                (uint256 cancelable, uint256 claimable) = _getLiquidity(bookKeyB, orderListB[i]);
                liquidityA += claimable;
                liquidityB += cancelable;
            }
        }
    }

    function _getLiquidity(IBookManager.BookKey memory bookKey, OrderId orderId)
        internal
        view
        returns (uint256 cancelable, uint256 claimable)
    {
        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(orderId);
        cancelable = uint256(orderInfo.open) * bookKey.unit;
        claimable = orderId.getTick().quoteToBase(uint256(orderInfo.claimable) * bookKey.unit, false);
        if (bookKey.makerPolicy.usesQuote()) {
            int256 fee = bookKey.makerPolicy.calculateFee(cancelable, true);
            cancelable = uint256(int256(cancelable) + fee);
        } else {
            int256 fee = bookKey.makerPolicy.calculateFee(claimable, false);
            claimable = fee > 0 ? claimable - uint256(fee) : claimable + uint256(-fee);
        }
    }

    function open(IBookManager.BookKey calldata bookKeyA, IBookManager.BookKey calldata bookKeyB, address strategy)
        external
        onlyOwner
        returns (bytes32)
    {
        return abi.decode(
            bookManager.lock(address(this), abi.encodeWithSelector(this._open.selector, bookKeyA, bookKeyB, strategy)),
            (bytes32)
        );
    }

    function mint(bytes32 key, uint256 amountA, uint256 amountB) external payable returns (uint256 mintAmount) {
        (uint256 liquidityA, uint256 liquidityB) = getLiquidity(key);
        Pool storage pool = _pools[key];
        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(pool.bookIdA);
        if (bookKeyA.quote.equals(CurrencyLibrary.NATIVE)) {
            if (msg.value != amountA) revert InvalidValue();
        } else {
            IERC20(Currency.unwrap(bookKeyA.quote)).safeTransferFrom(msg.sender, address(this), amountA);
        }
        if (bookKeyA.base.equals(CurrencyLibrary.NATIVE)) {
            if (msg.value != amountB) revert InvalidValue();
        } else {
            IERC20(Currency.unwrap(bookKeyA.base)).safeTransferFrom(msg.sender, address(this), amountB);
        }

        pool.reserveA += amountA;
        pool.reserveB += amountB;
        uint256 supply = totalSupply[uint256(key)];
        if (supply == 0) {
            mintAmount = amountA + pool.strategy.convertAmount(key, amountB, false);
        } else {
            uint256 amountALiquidityB = amountA * liquidityB;
            uint256 amountBLiquidityA = amountB * liquidityA;
            if (amountALiquidityB > amountBLiquidityA) {
                int256 fee = bookManager.getBookKey(pool.bookIdB).takerPolicy.calculateFee(liquidityA, false);
                uint256 denominator = fee > 0 ? liquidityA - uint256(fee) : liquidityA + uint256(-fee);
                denominator = pool.strategy.convertAmount(key, denominator, true) + liquidityB;
                uint256 numerator;
                unchecked {
                    numerator = amountALiquidityB - amountBLiquidityA;
                }
                mintAmount = FixedPointMathLib.mulDivDown(amountA - numerator / denominator, supply, liquidityA);
            } else {
                int256 fee = bookKeyA.takerPolicy.calculateFee(liquidityB, false);
                uint256 denominator = fee > 0 ? liquidityB - uint256(fee) : liquidityB + uint256(-fee);
                denominator = pool.strategy.convertAmount(key, denominator, false) + liquidityA;
                uint256 numerator;
                unchecked {
                    numerator = amountBLiquidityA - amountALiquidityB;
                }
                mintAmount = FixedPointMathLib.mulDivDown(amountB - numerator / denominator, supply, liquidityB);
            }
        }
        _mint(msg.sender, uint256(key), mintAmount);

        emit Mint(msg.sender, key, amountA, amountB, mintAmount);
    }

    function burn(bytes32 key, uint256 amount) external returns (uint256, uint256) {
        return abi.decode(
            bookManager.lock(
                address(this), abi.encodeWithSelector(this._burnAndRebalance.selector, key, msg.sender, amount)
            ),
            (uint256, uint256)
        );
    }

    function rebalance(bytes32 key) public {
        bookManager.lock(address(this), abi.encodeWithSelector(this._burnAndRebalance.selector, key, address(0), 0));
    }

    function lockAcquired(address lockCaller, bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(bookManager)) {
            revert InvalidLockAcquiredSender();
        }
        if (lockCaller != address(this)) {
            revert InvalidLockCaller();
        }

        (bool success, bytes memory returnData) = address(this).call(data);
        if (success) return returnData;
        if (returnData.length == 0) revert LockFailure();
        // if the call failed, bubble up the reason
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(returnData, 32), mload(returnData))
        }
    }

    function _open(IBookManager.BookKey calldata bookKeyA, IBookManager.BookKey calldata bookKeyB, address strategy)
        public
        selfOnly
        returns (bytes32 key)
    {
        if (!(bookKeyA.quote.equals(bookKeyB.base) && bookKeyA.base.equals(bookKeyB.quote))) revert InvalidBookPair();
        if (address(bookKeyA.hooks) != address(0) || address(bookKeyB.hooks) != address(0)) revert InvalidHook();
        bookManager.open(bookKeyA, "");
        bookManager.open(bookKeyB, "");
        BookId bookIdA = bookKeyA.toId();
        BookId bookIdB = bookKeyB.toId();

        key = _encodeKey(bookIdA, bookIdB);
        _pools[key].bookIdA = bookIdA;
        _pools[key].bookIdB = bookIdB;
        _pools[key].strategy = IStrategy(strategy);
        bookPair[bookIdA] = bookIdB;
        bookPair[bookIdB] = bookIdA;

        emit Open(key, bookIdA, bookIdB, strategy);
    }

    function _burnAndRebalance(bytes32 key, address user, uint256 burnAmount)
        public
        selfOnly
        returns (uint256 withdrawalA, uint256 withdrawalB)
    {
        Pool storage pool = _pools[key];
        if (pool.strategy == IStrategy(address(0))) revert InvalidBookPair();

        uint256 amountA = pool.reserveA;
        uint256 amountB = pool.reserveB;

        // Remove all orders
        (uint256 canceledAmount, uint256 claimedAmount) = _clearOrders(pool.orderListA);
        amountA += canceledAmount;
        amountB += claimedAmount;
        (canceledAmount, claimedAmount) = _clearOrders(pool.orderListB);
        amountA += claimedAmount;
        amountB += canceledAmount;

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(pool.bookIdA);
        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(pool.bookIdB);

        if (burnAmount > 0) {
            uint256 supply = totalSupply[uint256(key)];
            _burn(user, uint256(key), burnAmount);
            withdrawalA = FixedPointMathLib.mulDivDown(amountA, burnAmount, supply);
            withdrawalB = FixedPointMathLib.mulDivDown(amountB, burnAmount, supply);
            amountA -= withdrawalA;
            amountB -= withdrawalB;
            emit Burn(user, key, withdrawalA, withdrawalB, burnAmount);
        }

        // Compute allocation
        (IStrategy.Liquidity[] memory liquidityA, IStrategy.Liquidity[] memory liquidityB) =
            pool.strategy.computeAllocation(key, amountA, amountB);

        // @dev pool.orderListA.length == 0 && pool.orderListB.length == 0
        _setLiquidity(bookKeyA, liquidityA, pool.orderListA);
        _setLiquidity(bookKeyB, liquidityB, pool.orderListB);

        pool.reserveA = _settleCurrency(bookKeyA.quote, pool.reserveA);
        pool.reserveB = _settleCurrency(bookKeyA.base, pool.reserveB);

        if (withdrawalA > 0) {
            bookKeyA.quote.transfer(user, withdrawalA);
            pool.reserveA -= withdrawalA;
        }
        if (withdrawalB > 0) {
            bookKeyA.base.transfer(user, withdrawalB);
            pool.reserveB -= withdrawalB;
        }

        emit Rebalance(key);
    }

    function _clearOrders(OrderId[] storage orderIds)
        internal
        returns (uint256 canceledAmount, uint256 claimedAmount)
    {
        OrderId[] memory mOrderIds = orderIds;
        for (uint256 i = 0; i < mOrderIds.length; ++i) {
            OrderId orderId = mOrderIds[i];
            IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(orderId);
            if (orderInfo.claimable > 0) {
                claimedAmount += bookManager.claim(orderId, "");
            }
            if (orderInfo.open > 0) {
                canceledAmount += bookManager.cancel(IBookManager.CancelParams({id: orderId, to: 0}), "");
            }
        }
        assembly {
            sstore(orderIds.slot, 0)
        }
    }

    function _setLiquidity(
        IBookManager.BookKey memory bookKey,
        IStrategy.Liquidity[] memory liquidity,
        OrderId[] storage emptyOrderIds
    ) internal {
        for (uint256 i = 0; i < liquidity.length; ++i) {
            if (liquidity[i].rawAmount == 0) continue;
            (OrderId orderId,) = bookManager.make(
                IBookManager.MakeParams({
                    key: bookKey,
                    tick: liquidity[i].tick,
                    amount: liquidity[i].rawAmount,
                    provider: address(0)
                }),
                ""
            );
            emptyOrderIds.push(orderId);
        }
    }

    function _settleCurrency(Currency currency, uint256 liquidity) internal returns (uint256) {
        bookManager.settle(currency);

        int256 delta = bookManager.currencyDelta(address(this), currency);
        if (delta > 0) {
            currency.transfer(address(bookManager), uint256(delta));
            bookManager.settle(currency);
            liquidity -= uint256(delta);
        } else {
            bookManager.withdraw(currency, address(this), uint256(-delta));
            liquidity += uint256(-delta);
        }
        return liquidity;
    }

    function _encodeKey(BookId bookIdA, BookId bookIdB) internal pure returns (bytes32) {
        if (BookId.unwrap(bookIdA) > BookId.unwrap(bookIdB)) (bookIdA, bookIdB) = (bookIdB, bookIdA);
        return keccak256(abi.encodePacked(bookIdA, bookIdB));
    }

    function setStrategy(bytes32 key, address strategy) external onlyOwner {
        _pools[key].strategy = IStrategy(strategy);
    }

    receive() external payable {}
}
