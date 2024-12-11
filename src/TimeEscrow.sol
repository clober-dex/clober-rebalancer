// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITimeEscrow} from "./interfaces/ITimeEscrow.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract TimeEscrow is ITimeEscrow, Ownable2Step, Initializable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using BitMaps for BitMaps.BitMap;

    uint256 public escrowCounts;
    BitMaps.BitMap internal _escrowed;
    mapping(uint256 id => bytes32 proof) internal _proofs;

    constructor() Ownable(msg.sender) {}

    function initialize(address initialOwner) public initializer {
        _transferOwnership(initialOwner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function isEscrowed(uint256 id) external view returns (bool) {
        return _escrowed.get(id);
    }

    function getProof(uint256 id) external view returns (bytes32) {
        return _proofs[id];
    }

    function lock(address account, address token, uint256 amount, uint256 unlockTime)
        external
        payable
        returns (uint256 id)
    {
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) {
            if (msg.value != amount) revert InvalidAmount();
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        bytes32 key = _encodeKey(account, token, amount, unlockTime);
        id = escrowCounts++;
        _proofs[id] = key;
        _escrowed.setTo(id, true);

        emit Lock(msg.sender, account, token, amount, unlockTime, id);
    }

    function unlock(address account, address token, uint256 amount, uint256 unlockTime, uint256 id) external {
        if (!_escrowed.get(id)) revert InvalidProof();
        if (_proofs[id] != _encodeKey(account, token, amount, unlockTime)) {
            revert InvalidProof();
        }
        if (unlockTime > block.timestamp) revert Locked();

        _escrowed.setTo(id, false);
        if (token == address(0)) {
            (bool success,) = account.call{value: amount}("");
            if (!success) revert ValueTransferFailed();
        } else {
            IERC20(token).safeTransfer(account, amount);
        }

        emit Unlock(account, token, amount, unlockTime, id);
    }

    function _encodeKey(address account, address token, uint256 amount, uint256 unlockTime)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(account, token, amount, unlockTime));
    }
}
