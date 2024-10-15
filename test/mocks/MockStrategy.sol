// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {IStrategy} from "../../src/interfaces/IStrategy.sol";

contract MockStrategy is IStrategy {
    bool public shouldRevert;
    Order public orderA;
    Order public orderB;

    function computeOrders(bytes32, uint256, uint256)
        external
        view
        returns (Order[] memory ordersA, Order[] memory ordersB)
    {
        if (shouldRevert) {
            revert("MockStrategy: Revert");
        }
        ordersA = new Order[](1);
        ordersA[0] = orderA;
        ordersB = new Order[](1);
        ordersB[0] = orderB;
    }

    function setOrders(Order memory _orderA, Order memory _orderB) public {
        orderA = _orderA;
        orderB = _orderB;
    }

    function setShouldRevert(bool _shouldRevert) public {
        shouldRevert = _shouldRevert;
    }

    function mintHook(address sender, bytes32 key, uint256 mintAmount, bytes calldata hookData) external {}

    function burnHook(address sender, bytes32 key, uint256 burnAmount, bytes calldata hookData) external {}

    function rebalanceHook(address sender, bytes32 key, bytes calldata hookData) external {}
}
