// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

interface IFairLaunch {
    function alpacaPerBlock() external view returns (uint256);

    function pendingAlpaca(uint256 _pid, uint256 _user) external returns (uint256);

    struct _poolInfo {
        address stakeToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accAlpacaPerShare;
        uint256 accAlpacaPerShareTilBonusEnd;
    }

    struct _userInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 bonusDebt;
        address fundedBy;
    }

    function poolInfo(uint256 _pid) external returns (_poolInfo memory);

    function userInfo(uint256, address) external view returns (_userInfo memory);

    function deposit(address user, uint256 pid, uint256 amount) external;

    function harvest(uint256 pid) external;

    function withdraw(address _for, uint256 _pid, uint256 _amount) external;

    function alpaca() external view returns (address);
}
