// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import "./interfaces/ISimpleOracleStrategy.sol";
import "./interfaces/IRebalancer.sol";
import {IDatastreamOracle} from "./interfaces/IDatastreamOracle.sol";

contract Operator is UUPSUpgradeable, Initializable, Ownable2Step {
    IRebalancer public immutable rebalancer;

    constructor(IRebalancer rebalancer_) Ownable(msg.sender) {
        rebalancer = rebalancer_;
    }

    function initialize(address initialOwner) external initializer {
        _transferOwnership(initialOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function updatePosition(bytes32 key, uint256 oraclePrice, Tick tickA, Tick tickB, uint24 rate) external onlyOwner {
        ISimpleOracleStrategy oracleStrategy = ISimpleOracleStrategy(address(rebalancer.getPool(key).strategy));
        if (oracleStrategy.isPaused(key)) {
            oracleStrategy.unpause(key);
        }
        oracleStrategy.updatePosition(key, oraclePrice, tickA, tickB, rate);
        rebalancer.rebalance(key);
        IDatastreamOracle(address(oracleStrategy.referenceOracle())).request();
    }

    function pause(bytes32 key) external onlyOwner {
        ISimpleOracleStrategy(address(rebalancer.getPool(key).strategy)).pause(key);
        rebalancer.rebalance(key);
    }
}
