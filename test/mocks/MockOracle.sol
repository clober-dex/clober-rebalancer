// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {IOracle} from "../../src/interfaces/IOracle.sol";

contract MockOracle is IOracle {
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

    function setAssetPrice(address asset, uint256 price) external {
        _priceMap[asset] = price;
    }

    function setValidity(bool _isValid) external {
        isValid = _isValid;
    }
}
