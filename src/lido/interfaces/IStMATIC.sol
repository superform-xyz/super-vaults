// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

interface IStMATIC {
    function submit(uint256 _amount, address _referal) external returns (uint256);

    function approve(address, uint256) external returns (bool);

    function balanceOf(address) external view returns (uint256);

    function convertStMaticToMatic(uint256 _amountInStMatic)
        external
        view
        returns (uint256 amountInMatic, uint256 totalStMaticAmount, uint256 totalPooledMatic);

    function convertMaticToStMatic(uint256 _amountInMatic)
        external
        view
        returns (uint256 amountInStMatic, uint256 totalStMaticAmount, uint256 totalPooledMatic);
}
