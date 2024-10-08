// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {AggregatorV3Interface} from "../external/chainlink/AggregatorV3Interface.sol";
import {IOracle} from "../interfaces/IOracle.sol";
import {IChainlinkOracle} from "../interfaces/IChainlinkOracle.sol";

contract ChainlinkOracle is IChainlinkOracle, Ownable2Step {
    uint256 private constant _MAX_TIMEOUT = 1 days;
    uint256 private constant _MIN_TIMEOUT = 20 minutes;
    uint256 private constant _MAX_GRACE_PERIOD = 1 days;
    uint256 private constant _MIN_GRACE_PERIOD = 20 minutes;

    uint256 public override timeout;
    address public override sequencerOracle;
    uint256 public override gracePeriod;
    address public override fallbackOracle;
    mapping(address => address[]) private _feeds;

    constructor(address sequencerOracle_, uint256 timeout_, uint256 gracePeriod_, address initialOwner)
        Ownable(initialOwner)
    {
        _setSequencerOracle(sequencerOracle_);
        _setTimeout(timeout_);
        _setGracePeriod(gracePeriod_);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function getFeeds(address asset) external view returns (address[] memory) {
        return _feeds[asset];
    }

    function getAssetPrice(address asset) public view returns (uint256) {
        address[] memory feeds = _feeds[asset];
        if (feeds.length == 0) {
            return IOracle(fallbackOracle).getAssetPrice(asset);
        }
        uint256 price = 10 ** 8;
        for (uint256 i = 0; i < feeds.length; ++i) {
            try AggregatorV3Interface(feeds[i]).latestRoundData() returns (
                uint80 roundId, int256 answer, uint256, /* startedAt */ uint256 updatedAt, uint80 /* answeredInRound */
            ) {
                if (
                    roundId != 0 && answer >= 0 && updatedAt <= block.timestamp
                        && block.timestamp <= updatedAt + timeout && _isSequencerValid()
                ) {
                    uint256 feedDecimals = AggregatorV3Interface(feeds[i]).decimals();
                    price = price * uint256(answer) / 10 ** feedDecimals;
                    continue;
                }
            } catch {}
            return IOracle(fallbackOracle).getAssetPrice(asset);
        }
        return price;
    }

    function getAssetsPrices(address[] memory assets) external view returns (uint256[] memory prices) {
        prices = new uint256[](assets.length);
        unchecked {
            for (uint256 i = 0; i < assets.length; ++i) {
                prices[i] = getAssetPrice(assets[i]);
            }
        }
    }

    function isSequencerValid() external view returns (bool) {
        return _isSequencerValid();
    }

    function setFallbackOracle(address newFallbackOracle) external onlyOwner {
        fallbackOracle = newFallbackOracle;
        emit SetFallbackOracle(newFallbackOracle);
    }

    function setFeeds(address[] calldata assets, address[][] calldata feeds) external onlyOwner {
        if (assets.length != feeds.length) revert LengthMismatch();

        for (uint256 i = 0; i < assets.length; ++i) {
            if (feeds[i].length == 0) revert LengthMismatch();
            address[] storage _f = _feeds[assets[i]];
            assembly {
                sstore(_f.slot, 0)
            }
            for (uint256 j = 0; j < feeds[i].length; ++j) {
                _f.push(feeds[i][j]);
            }
            emit SetFeed(assets[i], feeds[i]);
        }
    }

    function setSequencerOracle(address newSequencerOracle) external onlyOwner {
        _setSequencerOracle(newSequencerOracle);
    }

    function _setSequencerOracle(address newSequencerOracle) internal {
        sequencerOracle = newSequencerOracle;
        emit SetSequencerOracle(newSequencerOracle);
    }

    function setTimeout(uint256 newTimeout) external onlyOwner {
        _setTimeout(newTimeout);
    }

    function _setTimeout(uint256 newTimeout) internal {
        if (newTimeout < _MIN_TIMEOUT || newTimeout > _MAX_TIMEOUT) revert InvalidTimeout();
        timeout = newTimeout;
        emit SetTimeout(newTimeout);
    }

    function setGracePeriod(uint256 newGracePeriod) external onlyOwner {
        _setGracePeriod(newGracePeriod);
    }

    function _setGracePeriod(uint256 newGracePeriod) internal {
        if (newGracePeriod < _MIN_GRACE_PERIOD || newGracePeriod > _MAX_GRACE_PERIOD) revert InvalidGracePeriod();
        gracePeriod = newGracePeriod;
        emit SetGracePeriod(newGracePeriod);
    }

    function _isSequencerValid() internal view returns (bool) {
        // @dev When the chain is L1, sequencerOracle is not set and always returns true.
        if (sequencerOracle == address(0)) {
            return true;
        }
        (, int256 answer,, uint256 updatedAt,) = AggregatorV3Interface(sequencerOracle).latestRoundData();
        return answer == 0 && block.timestamp - updatedAt > gracePeriod;
    }
}
