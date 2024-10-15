// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Tick} from "clober-dex/v2-core/libraries/Tick.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";

import {IStrategy} from "./IStrategy.sol";
import {IOracle} from "./IOracle.sol";
import "./IRebalancer.sol";

interface ISimpleOracleStrategy is IStrategy {
    error InvalidPrice();
    error InvalidConfig();
    error InvalidValue();
    error ExceedsThreshold();
    error NotOperator();

    event SetOperator(address indexed operator, bool status);
    event UpdateConfig(bytes32 indexed key, Config config);
    event UpdatePrice(bytes32 indexed key, uint256 oraclePrice, Tick tickA, Tick tickB, uint256 alpha);

    struct Config {
        uint24 referenceThreshold;
        uint24 rateA;
        uint24 rateB;
        uint24 minRateA;
        uint24 minRateB;
        uint24 priceThresholdA;
        uint24 priceThresholdB;
    }

    struct Price {
        uint208 oraclePrice;
        Tick tickA;
        Tick tickB;
    }

    function referenceOracle() external view returns (IOracle);

    function bookManager() external view returns (IBookManager);

    function isOperator(address operator) external view returns (bool);

    function getConfig(bytes32 key) external view returns (Config memory);

    function getPrice(bytes32 key) external view returns (Price memory);

    function getAlpha() external view returns (uint256);

    function isOraclePriceValid(bytes32 key) external view returns (bool);

    function updatePrice(bytes32 key, uint256 oraclePrice, Tick tickA, Tick tickB, uint256 alpha) external;

    function setConfig(bytes32 key, Config memory config) external;

    function setOperator(address operator, bool status) external;
}
