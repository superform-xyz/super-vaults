// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.10;
// import {SafeTransferLib, ERC20} from "solmate/utils/SafeTransferLib.sol";
// import {IRewadsCore} from "../interfaces/IRewardsCore.sol";
// interface IUnitroller {
//     function rewardSupplyState(uint8,address) returns (uint256,uint32);
// }

// interface CToken {
//     function comptroller() external view virtual returns (address);

//     function getCash() external view virtual returns (uint256);

//     function getAccountSnapshot(address)
//         external
//         view
//         virtual
//         returns (
//             uint256,
//             uint256,
//             uint256,
//             uint256
//         );
//     function underlying() external view virtual returns (address);
//     function redeemUnderlying(uint256) external virtual returns (uint256);
//     function mint(uint256) external virtual returns (uint256);
    
//     function exchangeRateStored() external virtual view returns (uint);
// }

// /// @title Rewards Claiming Contract
// /// @author joeysantoro
// contract BenqiRewardsClaimer is IRewadsCore{
//     using SafeTransferLib for ERC20;

//     event RewardDestinationUpdate(address indexed newDestination);

//     event ClaimRewards(address indexed rewardToken, uint256 amount);

//     /// @notice the address to send rewards
//     address public rewardDestination;

//     /// @notice the array of reward tokens to send to
//     ERC20[] public rewardTokens;

//     IUnitroller public unitroller;

//     uint256 mantissaConstant = 1e36;

//     CToken cToken;

//     struct depositIndex {
//         uint256 index;
//         uint256 amount;
//     }
//     // user => (rewardTokenIndex => supplyIndex)
//     mapping(address => mapping(uint8 => depositIndex)) public userDepositIndex;
//     constructor(address _rewardDestination, ERC20[] memory _rewardTokens, address _unitroller, address _cToken) {
//         rewardDestination = _rewardDestination;
//         rewardTokens = _rewardTokens;
//         unitroller = IUnitroller(_unitroller);
//         cToken = CToken(_cToken);
//     }

//     function updateDeposits(address user,uint256 qiTokens) external {
//         for (uint8 rewardIndex = 0; rewardIndex < rewardTokens.length; ++rewardIndex) {
//             (uint256 currentSupplyIndex,) = unitroller.rewardSupplyState(rewardIndex, cToken.address);
//             depositIndex memory currentIndex = userDepositIndex[user][rewardIndex];
//             if(currentIndex.index == 0){
//                 currentIndex.index = mantissaConstant;
//             }else{
//                 currentIndex.index = currentSupplyIndex;
//                 currentIndex.amount = qiTokens;
//             }
//             userDepositIndex[user][rewardIndex] = currentIndex;
//         }
        
//     }

//     function beforeWithdraw(address user, uint256 cTokenWithdrawn) external {
//         for (uint8 rewardIndex = 0; rewardIndex < array.length; ++rewardIndex) {
//             depositIndex memory currentIndex = userDepositIndex[user][rewardIndex];
//             (uint256 currentSupplyIndex,) = unitroller.rewardSupplyState(rewardIndex, cToken.address);
//             uint256 deltaIndex = currentSupplyIndex - currentIndex.index;
//             uint256 supplierDelta = (deltaIndex * currentIndex.amount) / mantissaConstant;
//             currentIndex.index = currentSupplyIndex;
//             currentIndex.amount -= underlyingWithdrawn
//         }
//     }

//     /// @notice claim all token rewards
//     function claimRewards() external {
//         beforeClaim(); // hook to accrue/pull in rewards, if needed

//         uint256 len = rewardTokens.length;
//         // send all tokens to destination
//         for (uint256 i = 0; i < len; i++) {
//             ERC20 token = rewardTokens[i];
//             uint256 amount = token.balanceOf(address(this));

//             token.safeTransfer(rewardDestination, amount);

//             emit ClaimRewards(address(token), amount);
//         }
//     }

//     /// @notice set the address of the new reward destination
//     /// @param newDestination the new reward destination
//     function setRewardDestination(address newDestination) external {
//         require(msg.sender == rewardDestination, "UNAUTHORIZED");
//         rewardDestination = newDestination;
//         emit RewardDestinationUpdate(newDestination);
//     }

//     /// @notice hook to accrue/pull in rewards, if needed
//     function beforeClaim() internal virtual {}
// }