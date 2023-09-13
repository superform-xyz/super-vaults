// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

interface IBComptroller {
    function qiAddress() external view returns (address);

    function getAllMarkets() external view returns (address[] memory);

    function allMarkets(uint256 index) external view returns (address);

    function claimReward(uint8 rewardType, address holder) external;

    function mintGuardianPaused(address cToken) external view returns (bool);

    function rewardAccrued(uint8, address) external view returns (uint256);

    struct RewardMarketState {
        /// @notice The market's last updated rewardBorrowIndex or rewardSupplyIndex
        uint224 index;
        /// @notice The block timestamp the index was last updated at
        uint32 timestamp;
    }

    function rewardSupplyState(uint8, address) external view returns (uint224, uint32);
}
