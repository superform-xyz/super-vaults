// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {DexSwap} from "../swapUtils.sol";

contract Harvester {
    address public  manager;
    address public  rewardTokenAddr;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    ERC20 public underlying;
    ERC20 public rewardToken;
    ERC4626 public vault;

    /// Compact struct to make two swaps (on Uniswap v2)
    /// A => B (using pair1) then B => underlying (of Wrapper) (using pair2)
    /// will work fine as long we only get 1 type of reward token
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    constructor() {
        manager = msg.sender;
    }

    function setVault(
        ERC4626 vault_,
        ERC20 rewardToken_
    ) external {
        require(msg.sender == manager, "onlyOwner");
        vault = vault_;
        underlying = vault.asset();
        rewardToken = rewardToken_;
        rewardTokenAddr = address(rewardToken);
    }

    function setRoute(
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        SwapInfo = swapInfo(token, pair1, pair2);
        rewardToken.approve(SwapInfo.pair1, type(uint256).max); /// max approves address
        ERC20(SwapInfo.token).approve(SwapInfo.pair2, type(uint256).max); /// max approves address
    }

    function harvest() external {

        /// Implement rewards distributor contract directly in the wrapper harvest()

        uint256 earned = ERC20(rewardToken).balanceOf(address(vault));

        /// If one swap needed (high liquidity pair) - set swapInfo.token0/token/pair2 to 0x
        if (SwapInfo.token == address(underlying)) {
            DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardTokenAddr, // from REWARD-TOKEN
                address(underlying), /// to target underlying of this Vault
                SwapInfo.pair1 /// pairToken (pool)
            );
            /// If two swaps needed
        } else {
            uint256 swapTokenAmount = DexSwap.swap(
                earned,
                rewardTokenAddr, // from AAVE-Fork
                SwapInfo.token, /// to intermediary token with high liquidity (no direct pools)
                SwapInfo.pair1 /// pairToken (pool)
            );

            swapTokenAmount = DexSwap.swap(
                swapTokenAmount,
                SwapInfo.token, // from received token
                address(underlying), /// to target underlying of this Vault
                SwapInfo.pair2 /// pairToken (pool)
            );
        }

        /// reinvest() without minting (no asset.totalSupply() increase == profit)
        /// afterDeposit just makes totalAssets() aToken's balance growth (to be distributed back to share owners)
        rewardToken.transfer(address(vault), underlying.balanceOf(address(this)));
    }
}
