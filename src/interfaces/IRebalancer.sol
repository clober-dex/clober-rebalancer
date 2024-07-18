// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {ILocker} from "clober-dex/v2-core/interfaces/ILocker.sol";
import {BookId, BookIdLibrary} from "clober-dex/v2-core/libraries/BookId.sol";
import {Currency, CurrencyLibrary} from "clober-dex/v2-core/libraries/Currency.sol";
import {OrderId, OrderIdLibrary} from "clober-dex/v2-core/libraries/OrderId.sol";
import {Tick, TickLibrary} from "clober-dex/v2-core/libraries/Tick.sol";
import {FeePolicy, FeePolicyLibrary} from "clober-dex/v2-core/libraries/FeePolicy.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ERC6909Supply} from "../libraries/ERC6909Supply.sol";

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

    function getLiquidity(bytes32 key) external view returns (uint256 liquidityA, uint256 liquidityB);

    function open(IBookManager.BookKey calldata bookKeyA, IBookManager.BookKey calldata bookKeyB, address strategy)
        external
        returns (bytes32 key);

    function mint(bytes32 key, uint256 amountA, uint256 amountB) external payable returns (uint256);

    function burn(bytes32 key, uint256 amount) external returns (uint256, uint256);

    function rebalance(bytes32 key) external;
}
