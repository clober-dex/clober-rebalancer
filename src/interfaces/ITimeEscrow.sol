// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ITimeEscrow {
    event Locked(
        address indexed depositor,
        address indexed account,
        address indexed token,
        uint256 amount,
        uint256 unlockTime,
        uint256 id
    );
    event Unlocked(address indexed account, address indexed token, uint256 amount, uint256 unlockTime, uint256 id);

    function isEscrowed(UnlockParams calldata params) external view returns (bool);

    function lock(address account, address token, uint256 amount, uint256 unlockTime)
        external
        payable
        returns (uint256 id);

    struct UnlockParams {
        address account;
        address token;
        uint256 amount;
        uint256 unlockTime;
        uint256 id;
    }

    function unlock(UnlockParams calldata params) external;

    function unlockAll(UnlockParams[] calldata params) external returns (bool[] memory results);
}
