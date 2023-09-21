// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import { ICERC20 } from "./ICERC20.sol";

interface IComptroller {
    function getAllMarkets() external view returns (ICERC20[] memory);

    function allMarkets(uint256 index) external view returns (ICERC20);

    function claimComp(address holder) external;

    function claimComp(address holder, ICERC20[] memory cTokens) external;

    function mintGuardianPaused(ICERC20 cToken) external view returns (bool);

    function rewardAccrued(uint8, address) external view returns (uint256);

    function enterMarkets(ICERC20[] memory cTokens) external returns (uint256[] memory);
}
