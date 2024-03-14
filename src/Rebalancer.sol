// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBookManager, BookId} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {ILocker} from "clober-dex/v2-core/interfaces/ILocker.sol";
import {Currency, CurrencyLibrary} from "clober-dex/v2-core/libraries/Currency.sol";
import {OrderId, OrderIdLibrary} from "clober-dex/v2-core/libraries/OrderId.sol";
import {Tick, TickLibrary} from "clober-dex/v2-core/libraries/Tick.sol";
import {FeePolicy, FeePolicyLibrary} from "clober-dex/v2-core/libraries/FeePolicy.sol";

import {IRebalancer} from "./interfaces/IRebalancer.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {BaseHook, Hooks} from "clober-dex/v2-core/hooks/BaseHook.sol";

contract Rebalancer is IRebalancer, ILocker, Ownable2Step, BaseHook {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using OrderIdLibrary for OrderId;
    using TickLibrary for Tick;
    using FeePolicyLibrary for FeePolicy;

    mapping(bytes32 key => address strategy) private _strategy;
    mapping(bytes32 key => uint256 amount) private _reserveA;
    mapping(bytes32 key => uint256 amount) private _reserveB;
    mapping(bytes32 key => OrderId[]) private _orderListA;
    mapping(bytes32 key => OrderId[]) private _orderListB;
    mapping(Currency currency => uint256 amount) private _readyToWithdraw;

    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    constructor(IBookManager bookManager_, address initialOwner_) Ownable(initialOwner_) BaseHook(bookManager_) {}

    function getHooksCalls() public pure override returns (Hooks.Permissions memory) {
        Hooks.Permissions memory permissions;
        permissions.afterOpen = true;
        permissions.beforeMake = true;
        permissions.beforeTake = true;
        return permissions;
    }

    function afterOpen(address, IBookManager.BookKey calldata, bytes calldata)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeMake(address, IBookManager.MakeParams calldata, bytes calldata)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function beforeTake(address, IBookManager.TakeParams calldata, bytes calldata)
        external
        override
        onlyBookManager
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function getLiquidity(BookId bookIdA, BookId bookIdB)
        public
        view
        returns (uint256 liquidityA, uint256 liquidityB)
    {
        bytes32 key = _encodeKey(bookIdA, bookIdB);
        liquidityA = _reserveA[key];
        liquidityB = _reserveB[key];

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(bookIdB);

        OrderId[] memory orderListA = _orderListA[key];
        OrderId[] memory orderListB = _orderListB[key];

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

    function registerStrategy(BookId bookIdA, BookId bookIdB, address strategy) external onlyOwner {
        bytes32 key = _encodeKey(bookIdA, bookIdB);
        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(bookIdB);
        if (!(bookKeyA.quote.equals(bookKeyB.base) && bookKeyA.base.equals(bookKeyB.quote))) revert InvalidBookPair();
        _strategy[key] = strategy;
    }

    function add(BookId bookIdA, BookId bookIdB, uint256 amountA, uint256 amountB) external onlyOwner {
        bytes32 key = _encodeKey(bookIdA, bookIdB);
        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        _readyToWithdraw[bookKeyA.quote] -= amountA;
        _readyToWithdraw[bookKeyA.base] -= amountB;
        _reserveA[key] += amountA;
        _reserveB[key] += amountB;
    }

    function cancelOrders(OrderId orderId, uint64 to) external onlyOwner {
        bookManager.lock(address(this), abi.encodeWithSelector(this._cancelOrder.selector, orderId, to));
    }

    function remove(BookId bookIdA, BookId bookIdB) external onlyOwner {
        bookManager.lock(address(this), abi.encodeWithSelector(this._remove.selector, bookIdA, bookIdB));
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

    function rebalance(BookId bookIdA, BookId bookIdB) public {
        // todo: check last block number and only allow rebalance every n blocks
        bookManager.lock(address(this), abi.encodeWithSelector(this._rebalance.selector, bookIdA, bookIdB));
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

    function _rebalance(BookId bookIdA, BookId bookIdB) public selfOnly {
        bytes32 key = _encodeKey(bookIdA, bookIdB);

        uint256 amountA = _reserveA[key];
        uint256 amountB = _reserveB[key];

        OrderId[] storage orderListA = _orderListA[key];
        OrderId[] storage orderListB = _orderListB[key];

        // Remove all orders
        (uint256 canceledAmount, uint256 claimedAmount) = _clearOrders(orderListA);
        amountA += canceledAmount;
        amountB += claimedAmount;
        (canceledAmount, claimedAmount) = _clearOrders(orderListB);
        amountA += claimedAmount;
        amountB += canceledAmount;

        // Compute allocation
        (IStrategy.Liquidity[] memory liquidityA, IStrategy.Liquidity[] memory liquidityB) =
            IStrategy(_strategy[key]).computeAllocation(bookIdA, amountA, bookIdB, amountB);

        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(bookIdA);
        IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(bookIdB);
        _setLiquidity(bookKeyA, liquidityA, orderListA);
        _setLiquidity(bookKeyB, liquidityB, orderListB);

        _reserveA[key] = _settleCurrency(bookKeyA.quote, amountA);
        _reserveB[key] = _settleCurrency(bookKeyA.base, amountB);
    }

    function _remove(BookId bookIdA, BookId bookIdB) public selfOnly {
        bytes32 key = _encodeKey(bookIdA, bookIdB);

        // Remove all orders
        _clearOrders(_orderListA[key]);
        _clearOrders(_orderListB[key]);

        IBookManager.BookKey memory bookKey = bookManager.getBookKey(bookIdA);
        _reserveA[key] = 0;
        _reserveB[key] = 0;
        _readyToWithdraw[bookKey.quote] += _settleCurrency(bookKey.quote, _reserveA[key]);
        _readyToWithdraw[bookKey.base] += _settleCurrency(bookKey.base, _reserveB[key]);
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

    function _encodeKey(BookId bookIdA, BookId bookIdB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bookIdA, bookIdB));
    }

    receive() external payable {}
}
