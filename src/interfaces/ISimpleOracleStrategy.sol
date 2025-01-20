// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Tick} from "clober-dex/v2-core/libraries/Tick.sol";
import {IBookManager} from "clober-dex/v2-core/interfaces/IBookManager.sol";

import {IStrategy} from "./IStrategy.sol";
import {IOracle} from "./IOracle.sol";
import "./IRebalancer.sol";

interface ISimpleOracleStrategy is IStrategy {
    error InvalidPrice();
    error InvalidAccess();
    error InvalidOraclePrice();
    error InvalidConfig();
    error InvalidValue();
    error ExceedsThreshold();
    error NotOperator();
    error Paused();

    event SetOperator(address indexed operator, bool status);
    event UpdateConfig(bytes32 indexed key, Config config);
    event UpdatePosition(bytes32 indexed key, uint256 oraclePrice, Tick tickA, Tick tickB, uint256 rate);
    event Pause(bytes32 indexed key);
    event Unpause(bytes32 indexed key);

    struct Config {
        uint24 referenceThreshold;
        uint24 rebalanceThreshold;
        uint24 rateA;
        uint24 rateB;
        uint24 minRateA;
        uint24 minRateB;
        uint24 priceThresholdA;
        uint24 priceThresholdB;
    }

    struct Position {
        bool paused;
        uint176 oraclePrice;
        uint24 rate;
        Tick tickA;
        Tick tickB;
    }

    /// @notice Returns the reference IOracle contract used by this strategy.
    function referenceOracle() external view returns (IOracle);

    /// @notice Returns the IBookManager instance controlling the underlying orderbooks.
    function bookManager() external view returns (IBookManager);

    /// @notice Checks if a given address is granted operator privileges.
    /// @param operator The address to query.
    /// @return True if the address is an operator, otherwise false.
    function isOperator(address operator) external view returns (bool);

    /// @notice Fetches the configuration (Config struct) for a specified key.
    /// @param key A unique identifier for the position or pool.
    /// @return The current Config struct associated with the key.
    function getConfig(bytes32 key) external view returns (Config memory);

    /// @notice Retrieves the position (Position struct) for a specified key.
    /// @param key A unique identifier for the position or pool.
    /// @return A Position struct containing paused state, oracle price, rate, tickA, and tickB.
    function getPosition(bytes32 key) external view returns (Position memory);

    /// @notice Returns two amounts recorded in the last operation for a specified key.
    /// @param key A unique identifier for the position or pool.
    /// @return (uint256, uint256) representing the two amounts (likely token A / token B).
    function getLastAmount(bytes32 key) external view returns (uint256, uint256);

    /// @notice Checks if the oracle price for the specified key is valid according to the strategy's criteria.
    /// @param key A unique identifier for the position or pool.
    /// @return True if the oracle price is valid, otherwise false.
    function isOraclePriceValid(bytes32 key) external view returns (bool);

    /// @notice Queries whether the position for a specified key is paused.
    /// @param key A unique identifier for the position or pool.
    /// @return True if paused, false otherwise.
    function isPaused(bytes32 key) external view returns (bool);

    /// @notice Pauses the position corresponding to the given key, preventing further updates or orders.
    /// @param key A unique identifier for the position or pool.
    function pause(bytes32 key) external;

    /// @notice Unpauses the position for the given key, allowing normal strategy operations to resume.
    /// @param key A unique identifier for the position or pool.
    function unpause(bytes32 key) external;

    /// @notice Updates the position parameters based on a newly fetched oracle price and tick ranges.
    /// @param key A unique identifier for the position or pool.
    /// @param oraclePrice The new oracle price used to guide the strategy.
    /// @param tickA The updated tick parameters for side A of the orderbook.
    /// @param tickB The updated tick parameters for side B of the orderbook.
    /// @param rate The multiplier applied at the final step of order amount calculation.
    function updatePosition(bytes32 key, uint256 oraclePrice, Tick tickA, Tick tickB, uint24 rate) external;

    /// @notice Updates the configuration settings for the specified key.
    /// @param key A unique identifier for the position or pool.
    /// @param config The new configuration parameters (thresholds, rates, etc.).
    function setConfig(bytes32 key, Config memory config) external;

    /// @notice Assigns or revokes operator permissions for a given address.
    /// @param operator The address whose operator status is being updated.
    /// @param status True to grant operator privileges, false to revoke.
    function setOperator(address operator, bool status) external;
}
