// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

interface IStMATIC {
    
    function submit(uint256 _amount) external returns (uint256);

    function approve(address, uint256) external returns (bool);

    function balanceOf(address) external view returns (uint256);
}