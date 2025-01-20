// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IOracle} from "./IOracle.sol";

interface IChainlinkOracle is IOracle {
    error LengthMismatch();
    error InvalidTimeout();
    error InvalidGracePeriod();
    error DifferentPrecision();

    event SetSequencerOracle(address indexed newSequencerOracle);
    event SetTimeout(uint256 newTimeout);
    event SetGracePeriod(uint256 newGracePeriod);
    event SetFallbackOracle(address indexed newFallbackOracle);
    event SetFeed(address indexed asset, address[] feeds);

    /// @notice Returns the address of the sequencer oracle contract.
    function sequencerOracle() external view returns (address);

    /// @notice Returns the timeout value (in seconds) after which oracle data is considered invalid.
    function timeout() external view returns (uint256);

    /// @notice Returns the grace period (in seconds) allowed after a sequencer outage before the feed is considered valid again.
    function gracePeriod() external view returns (uint256);

    /// @notice Returns the address of a fallback oracle used when Chainlink feeds are unavailable or invalid.
    function fallbackOracle() external view returns (address);

    /// @notice Retrieves the list of Chainlink feeds associated with a specific asset.
    /// @param asset The address of the asset.
    /// @return An array of feed addresses used for this asset.
    function getFeeds(address asset) external view returns (address[] memory);

    /// @notice Checks if the sequencer oracle deems the chain as properly sequenced.
    /// @return True if the sequencer oracle data is valid and chain is considered active.
    function isSequencerValid() external view returns (bool);

    /// @notice Sets a new fallback oracle address, used when the primary feeds are invalid or stale.
    /// @param newFallbackOracle The address of the new fallback oracle contract.
    function setFallbackOracle(address newFallbackOracle) external;

    /// @notice Updates the Chainlink feed addresses for multiple assets at once.
    /// @param assets The list of asset addresses to update.
    /// @param feeds The list of feed address arrays, each corresponding to an asset in `assets`.
    /// @dev The length of `assets` must match the length of `feeds`.
    function setFeeds(address[] calldata assets, address[][] calldata feeds) external;

    /// @notice Updates the sequencer oracle address, used to verify chain health/state.
    /// @param newSequencerOracle The address of the new sequencer oracle contract.
    function setSequencerOracle(address newSequencerOracle) external;

    /// @notice Updates the timeout value, after which feed data is considered stale.
    /// @param newTimeout The new timeout value in seconds.
    function setTimeout(uint256 newTimeout) external;

    /// @notice Updates the grace period value, controlling how long after a sequencer outage the feed data remains invalid.
    /// @param newGracePeriod The new grace period in seconds.
    function setGracePeriod(uint256 newGracePeriod) external;
}
