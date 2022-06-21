// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IRewardsCore} from "../interfaces/IRewardsCore.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/console.sol";

interface Unitroller {
    function claimReward(uint8 rewardType, address payable holder) external;
    function rewardAccrued(uint8 rewardType, address holder) external view returns(uint256);
    function comptrollerImplementation() external view returns(address);
}
contract BenqiClaimer is IRewardsCore, Ownable {
    Unitroller public unitroller;
    ERC20[] public rewardTokens;
    mapping(address => bool) public isRewardToken;
    uint8 numOfRewardTokens = 2;
    address payable public vault;
    constructor(
        address _unitroller
    ){
        unitroller = Unitroller(_unitroller);
        
    }

    function setVault(address _vault) external onlyOwner(){
        require(_vault != address(0));
        vault = payable(_vault);
    }


    function setRewardToken(address rewardToken) external onlyOwner() {
        require(!isRewardToken[rewardToken], "RewardToken already Added!");
        isRewardToken[rewardToken] = true;
        rewardTokens.push(ERC20(rewardToken));
    }

    function claimRewards() external {
        require(vault != address(0));
        for (uint8 index = 0; index < numOfRewardTokens; ++index) {
            unitroller.claimReward(index, vault);
        }
    }

    function rewardsAccrued(uint8 rewardType) external view returns (uint256) {
       return unitroller.rewardAccrued(rewardType, vault);
    }

    function claimRewardsByUser() external virtual {}
    function setRewardDestination() external virtual {}
    function updateDeposits(address user, uint256 amount) external virtual {}
    function beforeWithdraw(address user, uint256 amount) external virtual {}
}