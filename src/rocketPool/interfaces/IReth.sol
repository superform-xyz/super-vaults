// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

interface IRETH {

    function deposit() external payable;

    function balanceOf(address) external view returns (uint256);

}