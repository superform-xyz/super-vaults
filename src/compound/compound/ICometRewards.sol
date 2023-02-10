// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

interface ICometRewards {
    struct RewardConfig {
        address token;
        uint64 rescaleFactor;
        bool shouldUpscale;
    }
    function rewardConfig(address comet) external view returns(address token, uint64 rescaleFactor, bool shouldUpscale);
    function claim(address comet , address src, bool shouldAccrue) external;
}