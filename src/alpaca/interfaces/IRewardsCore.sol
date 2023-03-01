// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;
interface IRewardsCore {
    function claimRewards(
        address,
        address,
        bytes memory
    ) external;

    function claimRewards() external;

    function claimRewardsByUser() external;

    function setRewardDestination() external;

    function updateDeposits(address user, uint256 amount) external;

    function beforeWithdraw(address user, uint256 amount) external;
}
