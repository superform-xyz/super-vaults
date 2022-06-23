// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IRewardsCore} from "../interfaces/IRewardsCore.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/console.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

interface Unitroller {
    function claimReward(uint8 rewardType, address payable holder) external;
    function rewardAccrued(uint8 rewardType, address holder) external view returns(uint256);
    function comptrollerImplementation() external view returns(address);
}

interface IUniRouter {
    function factory() external view returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

interface IVault {
    function approveTokenIfNeeded(address,address) external;
}
contract BenqiClaimer is IRewardsCore, Ownable {
    using SafeTransferLib for ERC20;
    Unitroller public unitroller;
    ERC20[] public rewardTokens;
    mapping(address => bool) public isRewardToken;
    address payable public vault;
    IUniRouter public unirouter;
    
    constructor(
        address _unitroller,
        address _router
    ){
        unitroller = Unitroller(_unitroller);
        unirouter = IUniRouter(_router);
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
        for (uint8 index = 0; index < rewardTokens.length; ++index) {
            unitroller.claimReward(index, vault);
            ERC20 currRewardToken = rewardTokens[index];
            if(address(currRewardToken) != address(0)){
                IVault(vault).approveTokenIfNeeded(address(currRewardToken), address(this));
                currRewardToken.safeTransferFrom(vault,address(this),currRewardToken.balanceOf(vault));
            }
        }
    }

    function reinvest() external {
        
    }

    function rewardsAccrued(uint8 rewardType) external view returns (uint256) {
       return unitroller.rewardAccrued(rewardType, vault);
    }

    function claimRewardsByUser() external virtual {}
    function setRewardDestination() external virtual {}
    function updateDeposits(address user, uint256 amount) external virtual {}
    function beforeWithdraw(address user, uint256 amount) external virtual {}

    receive() external payable {}
}