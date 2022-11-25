// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

interface IComptroller {

    function qiAddress() external view returns (address);

    function getAllMarkets() external view returns (address[] memory);

    function allMarkets(uint256 index) external view returns (address);

    function claimReward(uint8 rewardType, address holder) external;

    function mintGuardianPaused(address cToken) external view returns (bool);

    function rewardAccrued(uint8, address) external view returns (uint256);
}
