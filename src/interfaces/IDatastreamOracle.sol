// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IOracle} from "./IOracle.sol";

interface IDatastreamOracle is IOracle {
    error InvalidForwarder();
    error InvalidReport();
    error NotOperator();
    error DifferentPrecision();

    struct FeedData {
        address asset;
        /// @dev The feed index starts from 1 rather than 0.
        uint96 index;
    }

    struct Report {
        bytes32 feedId; // The feed ID the report has data for
        uint32 validFromTimestamp; // Earliest timestamp for which price is applicable
        uint32 observationsTimestamp; // Latest timestamp for which price is applicable
        uint192 nativeFee; // Base cost to validate a transaction using the report, denominated in the chain’s native token (WETH/ETH)
        uint192 linkFee; // Base cost to validate a transaction using the report, denominated in LINK
        uint32 expiresAt; // Latest timestamp where the report can be verified onchain
        int192 price; // DON consensus median price, carried to 8 decimal places
        int192 bid; // Simulated price impact of a buy order up to the X% depth of liquidity utilisation
        int192 ask; // Simulated price impact of a sell order up to the X% depth of liquidity utilisation
    }

    event SetForwarder(address indexed forwarder);
    event SetFeed(address indexed asset, bytes32 feedId, uint256 index);
    event SetPrice(address indexed asset, uint256 price);
    event SetFallbackOracle(address indexed newFallbackOracle);
    event SetOperator(address indexed operator, bool status);
    event Request(address indexed requester, uint256 bitmap);

    /// @notice Checks if the specified account has operator privileges in this oracle system.
    /// @param account The address to check.
    /// @return True if `account` is an operator, false otherwise.
    function isOperator(address account) external view returns (bool);

    /// @notice Returns the address of the fallback oracle used when primary datastreams are invalid or unavailable.
    function fallbackOracle() external view returns (address);

    /// @notice Sets a new fallback oracle address.
    /// @param newFallbackOracle The address of the new fallback oracle contract.
    function setFallbackOracle(address newFallbackOracle) external;

    /// @notice Assigns a Chainlink/Datastream feed ID to a specific asset.
    /// @param feedId The unique feed ID representing data stream configuration on an off-chain system.
    /// @param asset The asset address for which this feed ID is being set.
    function setFeed(bytes32 feedId, address asset) external;

    /// @notice Sets the forwarder address, which may be used to route or handle oracle data externally.
    /// @param newForwarder The address of the forwarder contract.
    function setForwarder(address newForwarder) external;

    /// @notice Grants or revokes operator privileges for a given address.
    /// @param operator The address to be updated.
    /// @param status True to grant operator status, false to revoke.
    function setOperator(address operator, bool status) external;

    /// @notice Retrieves the list of all feed IDs currently registered in this oracle.
    /// @return An array of feed IDs (`bytes32`) managed by this contract.
    function getFeedIds() external view returns (bytes32[] memory);

    /// @notice Retrieves all feed data in bulk (feed IDs and corresponding asset info).
    /// @return feedIds An array of feed IDs.
    /// @return data An array of FeedData structs, each paired with the feedIds by index.
    function getAllFeedData() external view returns (bytes32[] memory feedIds, FeedData[] memory data);

    /// @notice Returns the address of the currently set forwarder contract.
    function forwarder() external view returns (address);

    /// @notice Returns the address of the fee token used for paying datastream fees.
    function feeToken() external view returns (address);

    /// @notice Returns the balance of the fee token held by this oracle contract.
    function feeBalance() external view returns (uint256);

    /// @notice Retrieves feed data (asset address, index) for a specific feed ID.
    /// @param feedId The ID of the feed to query.
    /// @return A FeedData struct containing asset info and feed index.
    function feedData(bytes32 feedId) external view returns (FeedData memory);

    /// @notice Sends a request with a specified bitmap to the oracle system.
    ///         The bitmap might represent which feeds or data sets the caller is requesting.
    /// @param bitmap A bitwise representation of requested data sets or feed IDs.
    function request(uint256 bitmap) external;
}
