// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Tick, TickLibrary} from "clober-dex/v2-core/libraries/Tick.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";
import {FeePolicy, FeePolicyLibrary} from "clober-dex/v2-core/libraries/FeePolicy.sol";
import {BookId} from "clober-dex/v2-core/libraries/BookId.sol";
import {Currency, CurrencyLibrary} from "clober-dex/v2-core/libraries/Currency.sol";

import {IStrategy} from "./IStrategy.sol";
import {IRebalancer} from "./IRebalancer.sol";
import {IOracle} from "./IOracle.sol";

interface ISimpleOracleStrategy is IStrategy {
    error InvalidPrice();
    error InvalidConfig();
    error ExceedsThreshold();
    error NotOperator();

    event SetOperator(address indexed operator, bool status);
    event UpdateConfig(bytes32 indexed key, Config config);
    event UpdatePrice(bytes32 indexed key, uint256 oraclePrice, Tick tickA, Tick tickB);

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
    function rebalancer() external view returns (IRebalancer);
    function bookManager() external view returns (IBookManager);
    function isOperator(address operator) external view returns (bool);
    function getConfig(bytes32 key) external view returns (Config memory);
    function getPrice(bytes32 key) external view returns (Price memory);
    function isOraclePriceValid(bytes32 key) external view returns (bool);
    function updatePrice(bytes32 key, uint256 oraclePrice, Tick tickA, Tick tickB) external;
    function setConfig(bytes32 key, Config memory config) external;
    function setOperator(address operator, bool status) external;
}
