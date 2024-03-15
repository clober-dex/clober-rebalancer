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

import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {BaseHook, Hooks} from "clober-dex/v2-core/hooks/BaseHook.sol";

contract Rebalancer is IRebalancer, ILocker, Ownable2Step, BaseHook {
    using BookIdLibrary for IBookManager.BookKey;
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using OrderIdLibrary for OrderId;
    using TickLibrary for Tick;
    using FeePolicyLibrary for FeePolicy;

    struct Pool {
        BookId bookIdA;
        BookId bookIdB;
        IStrategy strategy;
        uint32 rebalanceThreshold;
        uint64 lastRebalanceTimestamp;
        uint256 reserveA;
        uint256 reserveB;
        OrderId[] orderListA;
        OrderId[] orderListB;
    }

    mapping(bytes32 key => Pool) private _pools;
    mapping(BookId => BookId) private _bookPair;
    mapping(Currency currency => uint256 amount) private _readyToWithdraw;

    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    constructor(IBookManager bookManager_, address initialOwner_) BaseHook(bookManager_) Ownable(initialOwner_) {}

    function getHooksCalls() public pure override returns (Hooks.Permissions memory) {
        Hooks.Permissions memory permissions;
        permissions.beforeMake = true;
        permissions.beforeTake = true;
        return permissions;
    }

    function beforeMake(address sender, IBookManager.MakeParams calldata, bytes calldata)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        if (sender != address(this)) revert InvalidMaker();
        return this.beforeMake.selector;
    }

    function beforeTake(address, IBookManager.TakeParams calldata params, bytes calldata)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        BookId bookId = params.key.toId();
        BookId pairId = _bookPair[bookId];
        if (BookId.unwrap(pairId) == 0) revert InvalidBookPair();
        if (BookId.unwrap(bookId) > BookId.unwrap(pairId)) (bookId, pairId) = (pairId, bookId);

        rebalance(keccak256(abi.encodePacked(bookId, pairId)));

        return this.beforeTake.selector;
    }

    function getBookPairs(bytes32 key) external view returns (BookId, BookId) {
        Pool storage pool = _pools[key];
        return (pool.bookIdA, pool.bookIdB);
    }

    function getLiquidity(bytes32 key) public view returns (uint256 liquidityA, uint256 liquidityB) {
        Pool storage pool = _pools[key];
        liquidityA = pool.reserveA;
        liquidityB = pool.reserveB;

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(pool.bookIdA);
        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(pool.bookIdB);

        OrderId[] memory orderListA = pool.orderListA;
        OrderId[] memory orderListB = pool.orderListB;

        for (uint256 i; i < orderListA.length; ++i) {
            (uint256 cancelable, uint256 claimable) = _getLiquidity(bookKeyA, orderListA[i]);
            liquidityA += cancelable;
            liquidityB += claimable;
        }
        for (uint256 i; i < orderListB.length; ++i) {
            (uint256 cancelable, uint256 claimable) = _getLiquidity(bookKeyB, orderListB[i]);
            liquidityA += claimable;
            liquidityB += cancelable;
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

    function open(
        IBookManager.BookKey calldata bookKeyA,
        IBookManager.BookKey calldata bookKeyB,
        address strategy,
        uint32 rebalanceThreshold
    ) external onlyOwner returns (bytes32) {
        return abi.decode(
            bookManager.lock(
                address(this),
                abi.encodeWithSelector(this._open.selector, bookKeyA, bookKeyB, strategy, rebalanceThreshold)
            ),
            (bytes32)
        );
    }

    function add(bytes32 key, uint256 amountA, uint256 amountB) external onlyOwner {
        Pool storage pool = _pools[key];
        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(pool.bookIdA);
        _readyToWithdraw[bookKeyA.quote] -= amountA;
        _readyToWithdraw[bookKeyA.base] -= amountB;
        pool.reserveA += amountA;
        pool.reserveB += amountB;
    }

    function cancelOrders(OrderId orderId, uint64 to) external onlyOwner {
        bookManager.lock(address(this), abi.encodeWithSelector(this._cancelOrder.selector, orderId, to));
    }

    function remove(bytes32 key) external onlyOwner {
        bookManager.lock(address(this), abi.encodeWithSelector(this._remove.selector, key));
    }

    function deposit(Currency currency, uint256 amount) external payable {
        if (msg.value > 0) _readyToWithdraw[CurrencyLibrary.NATIVE] += msg.value;
        if (!currency.isNative()) {
            IERC20(Currency.unwrap(currency)).safeTransferFrom(msg.sender, address(this), amount);
            _readyToWithdraw[currency] += amount;
        }
    }

    function withdraw(Currency currency, address to, uint256 amount) external onlyOwner {
        _readyToWithdraw[currency] -= amount;
        currency.transfer(to, amount);
    }

    function rebalance(bytes32 key) public {
        bookManager.lock(address(this), abi.encodeWithSelector(this._rebalance.selector, key));
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

    function _open(
        IBookManager.BookKey calldata bookKeyA,
        IBookManager.BookKey calldata bookKeyB,
        address strategy,
        uint32 rebalanceThreshold
    ) public selfOnly returns (bytes32 key) {
        if (!(bookKeyA.quote.equals(bookKeyB.base) && bookKeyA.base.equals(bookKeyB.quote))) revert InvalidBookPair();
        bookManager.open(bookKeyA, "");
        bookManager.open(bookKeyB, "");
        BookId bookIdA = bookKeyA.toId();
        BookId bookIdB = bookKeyB.toId();
        if (BookId.unwrap(bookIdA) > BookId.unwrap(bookIdB)) (bookIdA, bookIdB) = (bookIdB, bookIdA);

        key = keccak256(abi.encodePacked(bookIdA, bookIdB));
        _pools[key].bookIdA = bookIdA;
        _pools[key].bookIdB = bookIdB;
        _pools[key].strategy = IStrategy(strategy);
        _pools[key].rebalanceThreshold = rebalanceThreshold;
        _bookPair[bookIdA] = bookIdB;
        _bookPair[bookIdB] = bookIdA;
    }

    function _rebalance(bytes32 key) public selfOnly {
        Pool storage pool = _pools[key];
        if (pool.strategy == IStrategy(address(0))) revert InvalidBookPair();
        if (block.timestamp < pool.lastRebalanceTimestamp + pool.rebalanceThreshold) return;

        uint256 amountA = pool.reserveA;
        uint256 amountB = pool.reserveB;

        // Remove all orders
        (uint256 canceledAmount, uint256 claimedAmount) = _clearOrders(pool.orderListA);
        amountA += canceledAmount;
        amountB += claimedAmount;
        (canceledAmount, claimedAmount) = _clearOrders(pool.orderListB);
        amountA += claimedAmount;
        amountB += canceledAmount;

        // Compute allocation
        (IStrategy.Liquidity[] memory liquidityA, IStrategy.Liquidity[] memory liquidityB) =
            pool.strategy.computeAllocation(pool.bookIdA, amountA, pool.bookIdB, amountB);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(pool.bookIdA);
        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(pool.bookIdB);
        _setLiquidity(bookKeyA, liquidityA, pool.orderListA);
        _setLiquidity(bookKeyB, liquidityB, pool.orderListB);

        pool.reserveA = _settleCurrency(bookKeyA.quote, amountA);
        pool.reserveB = _settleCurrency(bookKeyA.base, amountB);

        pool.lastRebalanceTimestamp = uint64(block.timestamp);
    }

    function _remove(bytes32 key) public selfOnly {
        Pool storage pool = _pools[key];

        // Remove all orders
        _clearOrders(pool.orderListA);
        _clearOrders(pool.orderListB);

        IBookManager.BookKey memory bookKey = bookManager.getBookKey(pool.bookIdA);
        _readyToWithdraw[bookKey.quote] += _settleCurrency(bookKey.quote, pool.reserveA);
        _readyToWithdraw[bookKey.base] += _settleCurrency(bookKey.base, pool.reserveB);
        pool.reserveA = 0;
        pool.reserveB = 0;
    }

    function _cancelOrder(OrderId orderId, uint64 to) public selfOnly {
        bookManager.cancel(IBookManager.CancelParams({id: orderId, to: to}), "");

        Currency quote = bookManager.getBookKey(orderId.getBookId()).quote;
        _readyToWithdraw[quote] = _settleCurrency(quote, _readyToWithdraw[quote]);
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
        OrderId[] storage orderIds
    ) internal {
        assembly {
            sstore(orderIds.slot, mload(liquidity))
        }
        for (uint256 i = 0; i < liquidity.length; ++i) {
            (OrderId orderId,) = bookManager.make(
                IBookManager.MakeParams({
                    key: bookKey,
                    tick: liquidity[i].tick,
                    amount: liquidity[i].rawAmount,
                    provider: address(0)
                }),
                ""
            );
            orderIds[i] = orderId;
        }
    }

    function _settleCurrency(Currency currency, uint256 liquidity) internal returns (uint256) {
        bookManager.settle(currency);

        int256 delta = bookManager.currencyDelta(address(this), currency);
        if (delta > 0) {
            bookManager.withdraw(currency, address(this), uint256(delta));
            liquidity += uint256(delta);
        } else {
            currency.transfer(address(bookManager), uint256(-delta));
            bookManager.settle(currency);
            liquidity -= uint256(-delta);
        }
        return liquidity;
    }

    receive() external payable {}
}
