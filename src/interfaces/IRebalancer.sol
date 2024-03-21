// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";
import {OrderId} from "clober-dex/v2-core/libraries/OrderId.sol";
import {Currency} from "clober-dex/v2-core/libraries/Currency.sol";
import {IStrategy} from "./IStrategy.sol";

interface IRebalancer {
    error NotSelf();
    error InvalidHook();
    error InvalidBookPair();
    error InvalidLockAcquiredSender();
    error InvalidLockCaller();
    error LockFailure();
    error InvalidMaker();

    event Open(
        bytes32 indexed key, BookId indexed bookIdA, BookId indexed bookIdB, address strategy, uint32 rebalanceThreshold
    );
    event Mint(address indexed user, bytes32 indexed key, uint256 amountA, uint256 amountB, uint256 lpAmount);

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

    function bookPair(BookId bookId) external view returns (BookId);

    function getPool(bytes32 key) external view returns (Pool memory);

    function getBookPairs(bytes32 key) external view returns (BookId bookIdA, BookId bookIdB);

    function getLiquidity(bytes32 key) external view returns (uint256 liquidityA, uint256 liquidityB);

    function open(
        IBookManager.BookKey calldata bookKeyA,
        IBookManager.BookKey calldata bookKeyB,
        address strategy,
        uint32 rebalanceThreshold
    ) external returns (bytes32 key);

    function mint(bytes32 key, uint256 amountA, uint256 amountB) external returns (uint256);

    function burn(bytes32 key, uint256 amount) external returns (uint256, uint256);

    function rebalance(bytes32 key) external;

    function setStrategy(bytes32 key, address strategy) external;

    function setRebalanceThreshold(bytes32 key, uint32 rebalanceThreshold) external;
}
