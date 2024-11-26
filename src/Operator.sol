// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {Currency, CurrencyLibrary} from "clober-dex/v2-core/libraries/Currency.sol";

import "./interfaces/ISimpleOracleStrategy.sol";
import "./interfaces/IRebalancer.sol";
import {IDatastreamOracle} from "./interfaces/IDatastreamOracle.sol";

contract Operator is UUPSUpgradeable, Initializable, Ownable2Step {
    using CurrencyLibrary for Currency;

    IRebalancer public immutable rebalancer;
    IDatastreamOracle public immutable datastreamOracle;

    constructor(IRebalancer rebalancer_, IDatastreamOracle datastreamOracle_) Ownable(msg.sender) {
        rebalancer = rebalancer_;
        datastreamOracle = datastreamOracle_;
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
    }

    function pause(bytes32 key) external onlyOwner {
        ISimpleOracleStrategy(address(rebalancer.getPool(key).strategy)).pause(key);
        rebalancer.rebalance(key);
    }

    function requestOraclePublic(uint256 bitmap) external {
        IERC20(datastreamOracle.feeToken()).transferFrom(msg.sender, address(this), 0.05 * 1e18);
        datastreamOracle.request(bitmap);
    }

    function requestOracle(uint256 bitmap) external onlyOwner {
        datastreamOracle.request(bitmap);
    }

    function withdraw(Currency currency, address to, uint256 amount) external onlyOwner {
        currency.transfer(to, amount);
    }
}
