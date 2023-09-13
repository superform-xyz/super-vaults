// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import {IGauge} from "./IGauge.sol";

interface IArrakisRouter {
    function addLiquidityAndStake(
        IGauge gauge,
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 amount0Min,
        uint256 amount1Min,
        address receiver
    ) external returns (uint256 amount0, uint256 amount1, uint256 mintAmount);
}
