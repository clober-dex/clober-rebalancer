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
        returns (Order[] memory ordersA, Order[] memory ordersB);

    function mintHook(address sender, bytes32 key, uint256 mintAmount, bytes calldata hookData) external;

    function burnHook(address sender, bytes32 key, uint256 burnAmount, bytes calldata hookData) external;

    function rebalanceHook(address sender, bytes32 key, bytes calldata hookData) external;
}
