// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IBInterestRateModel {
    function getBorrowRate(uint256, uint256, uint256) external view returns (uint256);

    function getSupplyRate(uint256, uint256, uint256, uint256) external view returns (uint256);
}
