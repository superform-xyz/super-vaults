// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {IRewardsCore} from "../interfaces/IRewardsCore.sol";
import {Ownable} from "openzeppelin-contracts/access/Ownable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import "forge-std/console.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {DexSwap} from "../utils/swapUtils.sol";

interface Unitroller {
    function claimReward(uint8 rewardType, address payable holder) external;
    function rewardAccrued(uint8 rewardType, address holder) external view returns(uint256);
    function comptrollerImplementation() external view returns(address);
}

interface IVault {
    function approveTokenIfNeeded(address,address) external;
    function cTokenUnderlying() external view returns(address);
}
interface IWrappedNative {
    function deposit() external payable;
    function balanceOf(address) external view returns(uint256);
}
contract BenqiClaimer is IRewardsCore, Ownable {
    using SafeTransferLib for ERC20;
    Unitroller public unitroller;
    ERC20[] public rewardTokens;
    mapping(address => bool) public isRewardToken;
    address payable public vault;
    IWrappedNative public wrappedNative;
    address private qiTokenSwap;
    address private depositTokenSwap;
    ERC20 public qiToken;
    constructor(
        address _unitroller,
        address _wrappedNative,
        address _qiTokenSwap,
        address _depositTokenSwap,
        address _qiToken
    ){
        unitroller = Unitroller(_unitroller);
        wrappedNative = IWrappedNative(_wrappedNative);
        qiTokenSwap = _qiTokenSwap;
        depositTokenSwap = _depositTokenSwap;
        qiToken = ERC20(_qiToken);
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
        unitroller.claimReward(0, vault);
        unitroller.claimReward(1, vault);
        IVault(vault).approveTokenIfNeeded(address(qiToken), address(this));
        qiToken.safeTransferFrom(vault,address(this),qiToken.balanceOf(vault));
        reinvest();
    }

    function reinvest() public {
       uint256 wNative = _convertRewardsToNative();
       uint256 depositTokenAmount = DexSwap.swap(wNative,address(wrappedNative), IVault(vault).cTokenUnderlying(), depositTokenSwap);
       if (ERC20(IVault(vault).cTokenUnderlying()).allowance(address(this), vault) == 0) {
            ERC20(IVault(vault).cTokenUnderlying()).safeApprove(vault, type(uint256).max);
        }
    }

    function _convertRewardsToNative() private returns(uint256) {
        uint256 avaxAmount = wrappedNative.balanceOf(address(this));
        uint256 balance = address(this).balance;
        if (balance > 0) {
            wrappedNative.deposit{value: balance}();
            avaxAmount = avaxAmount + (balance);
        }
        uint256 amount = qiToken.balanceOf(address(this));
        if (amount > 0 && address(qiTokenSwap) != address(0)) {
                avaxAmount = avaxAmount + (DexSwap.swap(amount, address(qiToken), address(wrappedNative), qiTokenSwap));
            }
        return avaxAmount;
    }

    function rewardsAccrued(uint8 rewardType) external view returns (uint256) {
       return unitroller.rewardAccrued(rewardType, vault);
    }

    function claimRewardsByUser() external virtual {}
    function setRewardDestination() external virtual {}
    function updateDeposits(address user, uint256 amount) external virtual {}
    function beforeWithdraw(address user, uint256 amount) external virtual {}

    function claimRewards(address, address, bytes calldata) external virtual {}

    receive() external payable {}
}