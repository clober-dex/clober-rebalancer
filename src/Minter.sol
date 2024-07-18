// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "./libraries/PermitParams.sol";
import "./Rebalancer.sol";

contract Minter {
    using CurrencyLibrary for Currency;
    using PermitParamsLibrary for *;
    using SafeERC20 for IERC20;

    error InsufficientBalance();
    error RouterSwapFailed(string message);
    error InsufficientLpAmount();

    IBookManager public immutable bookManager;
    Rebalancer public immutable rebalancer;
    address public immutable router;

    struct SwapParams {
        Currency inCurrency;
        uint256 amount;
        bytes data;
    }

    constructor(address _bookManager, address payable _rebalancer, address _router) {
        bookManager = IBookManager(_bookManager);
        rebalancer = Rebalancer(_rebalancer);
        router = _router;
    }

    function mint(
        bytes32 key,
        uint256 amountA,
        uint256 amountB,
        uint256 minLpAmount,
        ERC20PermitParams calldata currencyAPermitParams,
        ERC20PermitParams calldata currencyBPermitParams,
        SwapParams calldata swapParams
    ) external payable {
        (BookId bookIdA,) = rebalancer.getBookPairs(key);
        IBookManager.BookKey memory bookKey = IBookManager(bookManager).getBookKey(bookIdA);

        currencyAPermitParams.tryPermit(Currency.unwrap(bookKey.quote), msg.sender, address(this));
        currencyBPermitParams.tryPermit(Currency.unwrap(bookKey.base), msg.sender, address(this));

        if (bookKey.quote.isNative()) {
            if (address(this).balance < amountA) revert InsufficientBalance();
        } else {
            IERC20(Currency.unwrap(bookKey.quote)).safeTransferFrom(msg.sender, address(this), amountA);
        }

        if (bookKey.base.isNative()) {
            if (address(this).balance < amountB) revert InsufficientBalance();
        } else {
            IERC20(Currency.unwrap(bookKey.base)).safeTransferFrom(msg.sender, address(this), amountB);
        }

        _swap(swapParams);

        uint256 lpAmount = rebalancer.mint{value: address(this).balance}(
            key, bookKey.quote.balanceOfSelf(), bookKey.base.balanceOfSelf()
        );
        if (lpAmount < minLpAmount) revert InsufficientLpAmount();

        rebalancer.transfer(msg.sender, uint256(key), lpAmount);

        uint256 balance = bookKey.quote.balanceOfSelf();
        if (balance > 0) bookKey.quote.transfer(msg.sender, balance);
        balance = bookKey.base.balanceOfSelf();
        if (balance > 0) bookKey.base.transfer(msg.sender, balance);
    }

    function _swap(SwapParams calldata swapParams) internal {
        uint256 value;
        if (swapParams.inCurrency.isNative()) {
            value = swapParams.amount;
        } else {
            IERC20(Currency.unwrap(swapParams.inCurrency)).approve(router, swapParams.amount);
        }

        (bool success, bytes memory result) = router.call{value: value}(swapParams.data);
        if (!success) revert RouterSwapFailed(string(result));

        if (!swapParams.inCurrency.isNative()) {
            IERC20(Currency.unwrap(swapParams.inCurrency)).approve(router, 0);
        }
    }

    receive() external payable {}
}
