// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";
import {OrderId} from "clober-dex/v2-core/libraries/OrderId.sol";

import {IStrategy} from "./IStrategy.sol";

interface IPoolStorage {
    struct Pool {
        BookId bookIdA;
        BookId bookIdB;
        IStrategy strategy;
        bool paused;
        uint256 reserveA;
        uint256 reserveB;
        OrderId[] orderListA;
        OrderId[] orderListB;
    }

    function bookPair(BookId bookId) external view returns (BookId);

    function getPool(bytes32 key) external view returns (Pool memory);

    function getBookPairs(bytes32 key) external view returns (BookId bookIdA, BookId bookIdB);

    function setStrategy(bytes32 key, address strategy) external;
}
