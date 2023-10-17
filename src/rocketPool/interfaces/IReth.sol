// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

interface IRETH {
    function getBalance() external view returns (uint256);
    function getExcessBalance() external view returns (uint256);
    function recycleDissolvedDeposit() external payable;
    function recycleExcessCollateral() external payable;
    function recycleLiquidatedStake() external payable;
    function assignDeposits() external;
    function withdrawExcessBalance(uint256 _amount) external;
    function deposit() external payable;

    /// @dev Part of RocketBase parent contract
    function calcBase() external view returns (uint256);
}
