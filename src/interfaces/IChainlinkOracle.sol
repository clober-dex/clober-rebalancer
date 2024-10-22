// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IOracle} from "./IOracle.sol";

interface IChainlinkOracle is IOracle {
    error LengthMismatch();
    error InvalidTimeout();
    error InvalidGracePeriod();

    event SetSequencerOracle(address indexed newSequencerOracle);
    event SetTimeout(uint256 newTimeout);
    event SetGracePeriod(uint256 newGracePeriod);
    event SetFallbackOracle(address indexed newFallbackOracle);
    event SetFeed(address indexed asset, address[] feeds);

    function sequencerOracle() external view returns (address);

    function timeout() external view returns (uint256);

    function gracePeriod() external view returns (uint256);

    function fallbackOracle() external view returns (address);

    function getFeeds(address asset) external view returns (address[] memory);

    function isSequencerValid() external view returns (bool);

    function setFallbackOracle(address newFallbackOracle) external;

    function setFeeds(address[] calldata assets, address[][] calldata feeds) external;

    function setSequencerOracle(address newSequencerOracle) external;

    function setTimeout(uint256 newTimeout) external;

    function setGracePeriod(uint256 newGracePeriod) external;
}
