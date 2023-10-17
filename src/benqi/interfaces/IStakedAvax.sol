// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

interface IStakedAvax {
    function getSharesByPooledAvax(uint256 avaxAmount) external view returns (uint256);

    function getPooledAvaxByShares(uint256 shareAmount) external view returns (uint256);

    function approve(address, uint256) external returns (bool);

    function balanceOf(address) external view returns (uint256);

    function submit() external payable returns (uint256);
}
