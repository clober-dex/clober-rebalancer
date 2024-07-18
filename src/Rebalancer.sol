// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/IRebalancer.sol";
import "./interfaces/IPoolStorage.sol";

contract Rebalancer is IRebalancer, ILocker, Ownable2Step, ERC6909Supply, IPoolStorage {
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
        return (_pools[key].bookIdA, _pools[key].bookIdB);
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
                (uint256 cancelable, uint256 claimable) =
                    _getLiquidity(bookKeyA.makerPolicy, bookKeyA.unitSize, orderListA[i]);
                liquidityA += cancelable;
                liquidityB += claimable;
            }
        }
        if (orderListB.length > 0) {
            IBookManager.BookKey memory bookKeyB = bookManager.getBookKey(pool.bookIdB);
            for (uint256 i; i < orderListB.length; ++i) {
                (uint256 cancelable, uint256 claimable) =
                    _getLiquidity(bookKeyB.makerPolicy, bookKeyB.unitSize, orderListB[i]);
                liquidityA += claimable;
                liquidityB += cancelable;
            }
        }
    }

    function _getLiquidity(FeePolicy makerPolicy, uint64 unitSize, OrderId orderId)
        internal
        view
        returns (uint256 cancelable, uint256 claimable)
    {
        IBookManager.OrderInfo memory orderInfo = bookManager.getOrder(orderId);
        cancelable = uint256(orderInfo.open) * unitSize;
        claimable = orderId.getTick().quoteToBase(uint256(orderInfo.claimable) * unitSize, false);
        if (makerPolicy.usesQuote()) {
            int256 fee = makerPolicy.calculateFee(cancelable, true);
            cancelable = uint256(int256(cancelable) + fee);
        } else {
            int256 fee = makerPolicy.calculateFee(claimable, false);
            claimable = uint256(int256(claimable) - fee);
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
        Pool storage pool = _pools[key];
        IBookManager.BookKey memory bookKeyA = bookManager.getBookKey(pool.bookIdA);

        uint256 supply = totalSupply[uint256(key)];
        if (supply == 0) {
            if (amountA == 0 || amountB == 0) revert InvalidAmount();
            mintAmount = amountA > amountB ? amountA : amountB;
        } else {
            uint256 mintA;
            uint256 mintB;
            (uint256 liquidityA, uint256 liquidityB) = getLiquidity(key);
            if (liquidityA == 0) {
                amountA = 0;
            } else {
                mintA = FixedPointMathLib.mulDivDown(amountA, supply, liquidityA);
            }
            if (liquidityB == 0) {
                amountB = 0;
            } else {
                mintB = FixedPointMathLib.mulDivDown(amountB, supply, liquidityB);
            }

            if (mintA > mintB) {
                mintAmount = mintB;
                amountA = FixedPointMathLib.mulDivUp(liquidityA, mintAmount, supply);
            } else {
                mintAmount = mintA;
                amountB = FixedPointMathLib.mulDivUp(liquidityB, mintAmount, supply);
            }
        }

        uint256 refund = msg.value;
        if (bookKeyA.quote.isNative()) {
            if (msg.value < amountA) {
                revert InvalidValue();
            } else {
                unchecked {
                    refund -= amountA;
                }
            }
        } else {
            IERC20(Currency.unwrap(bookKeyA.quote)).safeTransferFrom(msg.sender, address(this), amountA);
        }
        if (bookKeyA.base.isNative()) {
            if (msg.value < amountB) {
                revert InvalidValue();
            } else {
                unchecked {
                    refund -= amountB;
                }
            }
        } else {
            IERC20(Currency.unwrap(bookKeyA.base)).safeTransferFrom(msg.sender, address(this), amountB);
        }

        pool.reserveA += amountA;
        pool.reserveB += amountB;

        _mint(msg.sender, uint256(key), mintAmount);

        emit Mint(msg.sender, key, amountA, amountB, mintAmount);

        if (refund > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, refund);
        }
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
        if (msg.sender != address(bookManager)) revert InvalidLockAcquiredSender();
        if (lockCaller != address(this)) revert InvalidLockCaller();

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

        BookId bookIdA = bookKeyA.toId();
        BookId bookIdB = bookKeyB.toId();
        if (!bookManager.isOpened(bookIdA)) bookManager.open(bookKeyA, "");
        if (!bookManager.isOpened(bookIdB)) bookManager.open(bookKeyB, "");

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
        (IStrategy.Order[] memory liquidityA, IStrategy.Order[] memory liquidityB) =
            pool.strategy.computeOrders(key, amountA, amountB);

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
                canceledAmount += bookManager.cancel(IBookManager.CancelParams({id: orderId, toUnit: 0}), "");
            }
        }
        assembly {
            sstore(orderIds.slot, 0)
        }
    }

    function _setLiquidity(
        IBookManager.BookKey memory bookKey,
        IStrategy.Order[] memory liquidity,
        OrderId[] storage emptyOrderIds
    ) internal {
        for (uint256 i = 0; i < liquidity.length; ++i) {
            if (liquidity[i].rawAmount == 0) continue;
            (OrderId orderId,) = bookManager.make(
                IBookManager.MakeParams({
                    key: bookKey,
                    tick: liquidity[i].tick,
                    unit: liquidity[i].rawAmount,
                    provider: address(0)
                }),
                ""
            );
            emptyOrderIds.push(orderId);
        }
    }

    function _settleCurrency(Currency currency, uint256 liquidity) internal returns (uint256) {
        bookManager.settle(currency);

        int256 delta = bookManager.getCurrencyDelta(address(this), currency);
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
        if (BookId.unwrap(bookIdA) > BookId.unwrap(bookIdB)) (bookIdA, bookIdB) = (bookIdB, bookIdA);
        return keccak256(abi.encodePacked(bookIdA, bookIdB));
    }

    function setStrategy(bytes32 key, address strategy) external onlyOwner {
        _pools[key].strategy = IStrategy(strategy);
    }

    receive() external payable {}
}
