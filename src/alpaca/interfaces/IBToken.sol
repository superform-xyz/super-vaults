// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IBToken {
    function deposit(uint256) external payable;

    function totalToken() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function config() external view returns (address);

    function token() external view returns (address);

    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function reservePool() external view returns (uint256);

    function vaultDebtVal() external view returns (uint256);

    function lastAccrueTime() external view returns (uint256);

    function pendingInterest(uint256 value) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}
