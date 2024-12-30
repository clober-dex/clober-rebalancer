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

    /// @notice Returns the IBookManager contract used by the Rebalancer.
    function bookManager() external view returns (IBookManager);

    /// @notice Returns the Rebalancer contract.
    function rebalancer() external view returns (Rebalancer);

    /// @notice Returns the router contract address used for performing swaps before minting.
    function router() external view returns (address);

    /// @notice Mints liquidity using the specified parameters, optionally performing a swap beforehand.
    /// @dev
    ///  1. Optionally calls `router` with `swapParams` if `inCurrency` is non-zero and `amount` > 0.
    ///  2. Approves tokens for Rebalancer and calls `mint()` on behalf of the user.
    /// @param key A unique key representing the liquidity pool in the Rebalancer.
    /// @param amountA The amount of token A to add as liquidity.
    /// @param amountB The amount of token B to add as liquidity.
    /// @param minLpAmount The minimum LP tokens the user is willing to receive; reverts if slippage is too high.
    /// @param currencyAPermitParams Permit parameters for token A (if needed).
    /// @param currencyBPermitParams Permit parameters for token B (if needed).
    /// @param swapParams Parameters for an optional swap to get token A or B.
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
