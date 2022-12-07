// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ICERC20} from "./ICERC20.sol";

interface IComptroller {

    function getXVSAddress() external view returns (address);

    function getAllMarkets() external view returns (ICERC20[] memory);

    function allMarkets(uint256 index) external view returns (ICERC20);

    function claimVenus(address holder) external;

    function venusAccrued(address user) external view returns (uint256 venusRewards);

    function mintGuardianPaused(ICERC20 cToken) external view returns (bool);
}
