// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IOracle} from "./IOracle.sol";

interface IDatastreamOracle is IOracle {
    error AlreadySetFeed();
    error InvalidForwarder();
    error InvalidReport();
    error NotOperator();

    struct FeedData {
        address asset;
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

    function isOperator(address account) external view returns (bool);

    function fallbackOracle() external view returns (address);

    function setFallbackOracle(address newFallbackOracle) external;

    function setFeed(bytes32 feedId, address asset) external;

    function setForwarder(address newForwarder) external;

    function setOperator(address operator, bool status) external;

    function getFeedIds() external view returns (bytes32[] memory);

    function getAllFeedData() external view returns (bytes32[] memory feedIds, FeedData[] memory data);

    function forwarder() external view returns (address);

    function feeToken() external view returns (address);

    function feeBalance() external view returns (uint256);

    function feedData(bytes32 feedId) external view returns (FeedData memory);

    function request(uint256 bitmap) external;
}
