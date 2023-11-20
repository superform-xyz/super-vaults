// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}
