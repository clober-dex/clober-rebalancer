// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";

interface IRebalancer {
    error NotSelf();
    error InvalidHook();
    error InvalidStrategy();
    error InvalidBookPair();
    error AlreadyOpened();
    error InvalidLockAcquiredSender();
    error InvalidLockCaller();
    error LockFailure();
    error InvalidMaker();
    error InvalidAmount();
    error InvalidValue();
    error Slippage();
    error Paused();

    event Open(bytes32 indexed key, BookId indexed bookIdA, BookId indexed bookIdB, bytes32 salt, address strategy);
    event Mint(address indexed user, bytes32 indexed key, uint256 amountA, uint256 amountB, uint256 lpAmount);
    event Burn(address indexed user, bytes32 indexed key, uint256 amountA, uint256 amountB, uint256 lpAmount);
    event Rebalance(bytes32 indexed key);
    event Pause(bytes32 indexed key, bool paused);
    event Claim(bytes32 indexed key, uint256 claimedAmountA, uint256 claimedAmountB);
    event Cancel(bytes32 indexed key, uint256 canceledAmountA, uint256 canceledAmountB);

    struct Liquidity {
        uint256 reserve;
        uint256 claimable;
        uint256 cancelable;
    }

    function getLiquidity(bytes32 key)
        external
        view
        returns (Liquidity memory liquidityA, Liquidity memory liquidityB);

    function open(
        IBookManager.BookKey calldata bookKeyA,
        IBookManager.BookKey calldata bookKeyB,
        bytes32 salt,
        address strategy
    ) external returns (bytes32 key);

    function mint(bytes32 key, uint256 amountA, uint256 amountB, uint256 minLpAmount)
        external
        payable
        returns (uint256);

    function burn(bytes32 key, uint256 amount, uint256 mintAmountA, uint256 minAmountB)
        external
        returns (uint256, uint256);

    function rebalance(bytes32 key) external;

    function pause(bytes32 key) external;

    function resume(bytes32 key) external;
}
