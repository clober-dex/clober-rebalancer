// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./interfaces/ISimpleOracleStrategy.sol";
import "./interfaces/IRebalancer.sol";

contract Operator is UUPSUpgradeable, Initializable, Ownable2Step {
    ISimpleOracleStrategy public immutable oracleStrategy;
    IRebalancer public immutable rebalancer;

    constructor(ISimpleOracleStrategy oracleStrategy_, IRebalancer rebalancer_) Ownable(msg.sender) {
        oracleStrategy = oracleStrategy_;
        rebalancer = rebalancer_;
    }

    function initialize(address initialOwner) external initializer {
        _transferOwnership(initialOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function updatePosition(bytes32 key, uint256 oraclePrice, Tick tickA, Tick tickB, uint24 rate) external onlyOwner {
        oracleStrategy.updatePosition(key, oraclePrice, tickA, tickB, rate);
        rebalancer.rebalance(key);
    }
}
