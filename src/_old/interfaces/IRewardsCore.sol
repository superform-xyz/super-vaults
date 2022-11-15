// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

interface IRewardsCore {
    function claimRewards(address, address, bytes memory) external;
    function claimRewards() external;
    function claimRewardsByUser() external;
    function setRewardDestination() external;
    function updateDeposits(address user, uint256 amount) external;
    function beforeWithdraw(address user, uint256 amount) external;
}
