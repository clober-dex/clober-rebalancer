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
    error InvalidMaker();

    function getBookPairs(bytes32 key) external view returns (BookId bookIdA, BookId bookIdB);

    function getLiquidity(bytes32 key) external view returns (uint256 liquidityA, uint256 liquidityB);

    function open(
        IBookManager.BookKey calldata bookIdA,
        IBookManager.BookKey calldata bookIdB,
        address strategy,
        uint32 rebalanceThreshold
    ) external returns (bytes32 key);

    function add(bytes32 key, uint256 amountA, uint256 amountB) external;

    function cancelOrders(OrderId orderId, uint64 to) external;

    function remove(bytes32 key) external;

    function deposit(Currency currency, uint256 amount) external payable;

    function withdraw(Currency currency, address to, uint256 amount) external;

    function rebalance(bytes32 key) external;
}
