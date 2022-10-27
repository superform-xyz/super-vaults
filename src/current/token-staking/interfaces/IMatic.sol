// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

interface IMATIC {
    function balanceOf(address) external view returns (uint256);

    function approve(address, uint256) external returns (bool);

    function deposit() external payable;

    function withdraw(uint256) external;

    function allowance(address, address) external returns (uint256);
}
