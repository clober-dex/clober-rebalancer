// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockSwap {
    using SafeERC20 for IERC20;

    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut) external {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }

    function swapEthForToken(address tokenOut, uint256 amountOut) external payable {
        require(msg.value > 0, "MockSwap: ETH value must be greater than 0");
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }
}
