// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "../libraries/PermitParams.sol";
import "../Rebalancer.sol";

interface IMinter {
    error RouterSwapFailed(bytes message);

    struct SwapParams {
        Currency inCurrency;
        uint256 amount;
        bytes data;
    }

    function bookManager() external view returns (IBookManager);

    function rebalancer() external view returns (Rebalancer);

    function router() external view returns (address);

    function mint(
        bytes32 key,
        uint256 amountA,
        uint256 amountB,
        uint256 minLpAmount,
        ERC20PermitParams calldata currencyAPermitParams,
        ERC20PermitParams calldata currencyBPermitParams,
        SwapParams calldata swapParams
    ) external payable;
}
