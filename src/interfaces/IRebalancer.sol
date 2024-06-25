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
    error InvalidAmount();
    error InvalidValue();

    event Open(bytes32 indexed key, BookId indexed bookIdA, BookId indexed bookIdB, address strategy);
    event Mint(address indexed user, bytes32 indexed key, uint256 amountA, uint256 amountB, uint256 lpAmount);
    event Burn(address indexed user, bytes32 indexed key, uint256 amountA, uint256 amountB, uint256 lpAmount);
    event Rebalance(bytes32 indexed key);

    struct Pool {
        BookId bookIdA;
        BookId bookIdB;
        IStrategy strategy;
        uint256 reserveA;
        uint256 reserveB;
        OrderId[] orderListA;
        OrderId[] orderListB;
    }

    function bookPair(BookId bookId) external view returns (BookId);

    function getPool(bytes32 key) external view returns (Pool memory);

    function getBookPairs(bytes32 key) external view returns (BookId bookIdA, BookId bookIdB);

    function getLiquidity(bytes32 key) external view returns (uint256 liquidityA, uint256 liquidityB);

    function open(IBookManager.BookKey calldata bookKeyA, IBookManager.BookKey calldata bookKeyB, address strategy)
        external
        returns (bytes32 key);

    function mint(bytes32 key, uint256 amountA, uint256 amountB) external payable returns (uint256);

    function burn(bytes32 key, uint256 amount) external returns (uint256, uint256);

    function rebalance(bytes32 key) external;

    function setStrategy(bytes32 key, address strategy) external;
}
