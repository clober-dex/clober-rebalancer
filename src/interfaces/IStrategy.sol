// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";
import {Tick} from "clober-dex/v2-core/libraries/Tick.sol";

interface IStrategy {
    struct Order {
        Tick tick;
        uint64 rawAmount;
    }

    function computeOrders(bytes32 key, uint256 amountA, uint256 amountB)
        external
        view
        returns (Order[] memory, Order[] memory);
}
