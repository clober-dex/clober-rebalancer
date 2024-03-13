// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "clober-dex/v2-core/interfaces/IBookManager.sol";
import "clober-dex/v2-core/interfaces/ILocker.sol";
import "clober-dex/v2-core/libraries/Tick.sol";

import "./interfaces/IRebalancer.sol";
import "./interfaces/IStrategy.sol";

contract Rebalancer is IRebalancer, ILocker, Ownable2Step {
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;
    using OrderIdLibrary for OrderId;

    IBookManager private immutable _bookManager;

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

    constructor(IBookManager bookManager_, address initialOwner_) Ownable(initialOwner_) {
        _bookManager = bookManager_;
    }

    function registerStrategy(BookId bookIdA, BookId bookIdB, address strategy) external onlyOwner {
        bytes32 key = _encodeKey(bookIdA, bookIdB);
        IBookManager.BookKey memory bookKeyA = _bookManager.getBookKey(bookIdA);
        IBookManager.BookKey memory bookKeyB = _bookManager.getBookKey(bookIdB);
        if (!(bookKeyA.quote.equals(bookKeyB.base) && bookKeyA.base.equals(bookKeyB.quote))) revert InvalidBookPair();
        _strategy[key] = strategy;
    }

    function add(BookId bookIdA, BookId bookIdB, uint256 amountA, uint256 amountB) external onlyOwner {
        bytes32 key = _encodeKey(bookIdA, bookIdB);
        IBookManager.BookKey memory bookKeyA = _bookManager.getBookKey(bookIdA);
        _readyToWithdraw[bookKeyA.quote] -= amountA;
        _readyToWithdraw[bookKeyA.base] -= amountB;
        _reserveA[key] += amountA;
        _reserveB[key] += amountB;
    }

    function cancelOrders(OrderId orderId, uint64 to) external onlyOwner {
        _bookManager.lock(address(this), abi.encodeWithSelector(this._cancelOrder.selector, orderId, to));
    }

    function remove(BookId bookIdA, BookId bookIdB) external onlyOwner {
        _bookManager.lock(address(this), abi.encodeWithSelector(this._remove.selector, bookIdA, bookIdB));
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

    function rebalance(BookId bookIdA, BookId bookIdB) external {
        _bookManager.lock(address(this), abi.encodeWithSelector(this._rebalance.selector, bookIdA, bookIdB));
    }

    function lockAcquired(address lockCaller, bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(_bookManager)) {
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

        // Remove all orders
        (uint256 canceledAmount, uint256 claimedAmount) = _clearOrders(_orderListA[key]);
        amountA += canceledAmount;
        amountB += claimedAmount;
        (canceledAmount, claimedAmount) = _clearOrders(_orderListB[key]);
        amountA += claimedAmount;
        amountB += canceledAmount;

        // Compute allocation
        (IStrategy.Liquidity[] memory liquidityA, IStrategy.Liquidity[] memory liquidityB) =
            IStrategy(_strategy[key]).computeAllocation(bookIdA, amountA, bookIdB, amountB);

        IBookManager.BookKey memory bookKeyA = _bookManager.getBookKey(bookIdA);
        IBookManager.BookKey memory bookKeyB = _bookManager.getBookKey(bookIdB);
        OrderId[] storage orderListA = _orderListA[key];
        OrderId[] storage orderListB = _orderListB[key];
        assembly {
            sstore(orderListA.slot, mload(liquidityA))
            sstore(orderListB.slot, mload(liquidityB))
        }
        _setLiquidity(bookKeyA, liquidityA, orderListA);
        _setLiquidity(bookKeyB, liquidityB, orderListB);

        Currency currencyA = bookKeyA.quote;
        Currency currencyB = bookKeyA.base;

        _reserveA[key] = _settleCurrency(currencyA, amountA);
        _reserveB[key] = _settleCurrency(currencyB, amountB);
    }

    function _remove(BookId bookIdA, BookId bookIdB) public selfOnly {
        bytes32 key = _encodeKey(bookIdA, bookIdB);

        // Remove all orders
        _clearOrders(_orderListA[key]);
        _clearOrders(_orderListB[key]);
        assembly {
            sstore(_orderListA.slot, 0)
            sstore(_orderListB.slot, 0)
        }

        IBookManager.BookKey memory bookKey = _bookManager.getBookKey(bookIdA);
        _reserveA[key] = 0;
        _reserveB[key] = 0;
        _readyToWithdraw[bookKey.quote] += _settleCurrency(bookKey.quote, _reserveA[key]);
        _readyToWithdraw[bookKey.base] += _settleCurrency(bookKey.base, _reserveB[key]);
    }

    function _cancelOrder(OrderId orderId, uint64 to) public selfOnly {
        _bookManager.cancel(IBookManager.CancelParams({id: orderId, to: to}), "");

        Currency quote = _bookManager.getBookKey(orderId.getBookId()).quote;
        _readyToWithdraw[quote] = _settleCurrency(quote, _readyToWithdraw[quote]);
    }

    function _clearOrders(OrderId[] memory orderIds) internal returns (uint256 canceledAmount, uint256 claimedAmount) {
        for (uint256 i = 0; i < orderIds.length; ++i) {
            OrderId orderId = orderIds[i];
            IBookManager.OrderInfo memory orderInfo = _bookManager.getOrder(orderId);
            if (orderInfo.claimable > 0) {
                claimedAmount += _bookManager.claim(orderId, "");
            }
            if (orderInfo.open > 0) {
                canceledAmount += _bookManager.cancel(IBookManager.CancelParams({id: orderId, to: 0}), "");
            }
        }
    }

    function _setLiquidity(
        IBookManager.BookKey memory bookKey,
        IStrategy.Liquidity[] memory liquidity,
        OrderId[] storage orderIds
    ) internal {
        for (uint256 i = 0; i < liquidity.length; ++i) {
            (OrderId orderId,) = _bookManager.make(
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
        _bookManager.settle(currency);

        int256 delta = _bookManager.currencyDelta(address(this), currency);
        if (delta > 0) {
            _bookManager.withdraw(currency, address(this), uint256(delta));
            liquidity += uint256(delta);
        } else {
            currency.transfer(address(_bookManager), uint256(-delta));
            _bookManager.settle(currency);
            liquidity -= uint256(-delta);
        }
        return liquidity;
    }

    function _encodeKey(BookId bookIdA, BookId bookIdB) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(bookIdA, bookIdB));
    }

    receive() external payable {}
}
