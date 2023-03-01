// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

interface IStETH {
    function getTotalShares() external view returns (uint256);

    function submit(address) external payable returns (uint256);

    function submit() external payable returns (uint256);

    function burnShares(address, uint256) external returns (uint256);

    function approve(address, uint256) external returns (bool);

    function sharesOf(address) external view returns (uint256);

    function userSharesInCustody(address) external view returns (uint256);

    function getPooledEthByShares(uint256) external view returns (uint256);

    function getSharesByPooledEth(uint256) external view returns (uint256);

    function getPooledAvaxByShares(uint256) external view returns (uint256);

    function getSharesByPooledAvax(uint256) external view returns (uint256);

    function balanceOf(address) external view returns (uint256);
}