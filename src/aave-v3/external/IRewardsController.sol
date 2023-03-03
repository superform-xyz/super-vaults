// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

/**
 * @title IRewardsController
 * @author Aave
 * @notice Defines the basic interface for a Rewards Controller.
 */
interface IRewardsController {
    function getAllUserRewards(address[] calldata assets, address user)
        external
        view
        returns (
            address[] memory rewardsList,
            uint256[] memory unclaimedAmounts
        );

    /**
     * @dev Returns the list of available reward token addresses of an incentivized asset
     * @param asset The incentivized asset
     * @return List of rewards addresses of the input asset
     **/

    function getRewardsByAsset(address asset)
        external
        view
        returns (address[] memory);

    /**
     * @dev Claims all rewards for a user to the desired address, on all the assets of the pool, accumulating the pending rewards
     * @param assets The list of assets to check eligible distributions before claiming rewards
     * @param to The address that will be receiving the rewards
     * @return rewardsList List of addresses of the reward tokens
     * @return claimedAmounts List that contains the claimed amount per reward, following same order as "rewardList"
     *
     */
    function claimAllRewards(address[] calldata assets, address to)
        external
        returns (address[] memory rewardsList, uint256[] memory claimedAmounts);
}
