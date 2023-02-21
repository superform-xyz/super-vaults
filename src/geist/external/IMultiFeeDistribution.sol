// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

interface IMultiFeeDistribution {

    struct RewardData {
        address token;
        uint256 amount;
    }
    
    function getReward() external;

    function exit() external;

    function claimableRewards(address account) external view returns (RewardData[] memory rewards);

    function unlockedBalance(address user) view external returns (uint256 amount);

}