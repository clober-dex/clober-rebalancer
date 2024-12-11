// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface ITimeEscrow {
    error InvalidAmount();
    error ValueTransferFailed();
    error InvalidProof();
    error Locked();

    event Lock(
        address indexed depositor,
        address indexed account,
        address token,
        uint256 amount,
        uint256 unlockTime,
        uint256 indexed id
    );
    event Unlock(
        address indexed account, address indexed token, uint256 amount, uint256 unlockTime, uint256 indexed id
    );

    function escrowCounts() external view returns (uint256);

    function isEscrowed(uint256 id) external view returns (bool);

    function getProof(uint256 id) external view returns (bytes32);

    function lock(address account, address token, uint256 amount, uint256 unlockTime)
        external
        payable
        returns (uint256 id);

    function unlock(address account, address token, uint256 amount, uint256 unlockTime, uint256 id) external;
}
