// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {IOracle} from "../../src/interfaces/IOracle.sol";

contract MockOracle is IOracle {
    uint256 public override timeout;
    uint256 public override gracePeriod;
    address public override sequencerOracle;

    mapping(address => uint256) private _priceMap;

    bool public isValid = true;

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function getAssetPrice(address asset) external view override returns (uint256) {
        return _priceMap[asset];
    }

    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory prices) {
        if (!isValid) revert("");
        uint256 length = assets.length;
        prices = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            prices[i] = _priceMap[assets[i]];
        }
    }

    function isSequencerValid() external pure returns (bool) {
        return true;
    }

    function setAssetPrice(address asset, uint256 price) external {
        _priceMap[asset] = price;
    }

    function fallbackOracle() external pure returns (address) {
        return address(0);
    }

    function getFeeds(address) external pure returns (address[] memory) {
        return new address[](0);
    }

    function setFallbackOracle(address) external {}

    function setFeeds(address[] calldata, address[][] calldata) external {}

    function setSequencerOracle(address) external {}

    function setTimeout(uint256) external {}

    function setGracePeriod(uint256) external {}

    function setValidity(bool _isValid) external {
        isValid = _isValid;
    }
}
