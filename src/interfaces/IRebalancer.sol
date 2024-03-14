// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";
import {OrderId} from "clober-dex/v2-core/libraries/OrderId.sol";
import {Currency} from "clober-dex/v2-core/libraries/Currency.sol";

interface IRebalancer {
    error NotSelf();
    error InvalidBookPair();
    error InvalidLockAcquiredSender();
    error InvalidLockCaller();
    error LockFailure();

    function getLiquidity(BookId bookIdA, BookId bookIdB)
        external
        view
        returns (uint256 liquidityA, uint256 liquidityB);

    function open(IBookManager.BookKey calldata bookIdA, IBookManager.BookKey calldata bookIdB, address strategy)
        external;

    function add(BookId bookIdA, BookId bookIdB, uint256 amountA, uint256 amountB) external;

    function cancelOrders(OrderId orderId, uint64 to) external;

    function remove(BookId bookIdA, BookId bookIdB) external;

    function deposit(Currency currency, uint256 amount) external payable;

    function withdraw(Currency currency, address to, uint256 amount) external;

    function rebalance(BookId bookIdA, BookId bookIdB) external;

    function setStrategy(BookId bookIdA, BookId bookIdB, address strategy) external;
}
