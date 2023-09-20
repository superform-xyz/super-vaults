// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

interface IInterestRateModel {
    function getBorrowRate(uint256, uint256, uint256) external view returns (uint256);

    function getSupplyRate(uint256, uint256, uint256, uint256) external view returns (uint256);
}
