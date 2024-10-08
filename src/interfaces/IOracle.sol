// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

interface IOracle {
    function decimals() external view returns (uint8);

    function getAssetPrice(address asset) external view returns (uint256);

    function getAssetsPrices(address[] calldata assets) external view returns (uint256[] memory);
}
