// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {CometMainInterface} from "./compound/IComet.sol";
import {LibCompound} from "./compound/LibCompound.sol";
import {ICometRewards} from "./compound/ICometRewards.sol";

import {DexSwap} from "./utils/swapUtils.sol";

/// @title CompoundV3StrategyWrapper - Custom implementation of yield-daddy wrappers with flexible reinvesting logic
/// Rationale: Forked protocols often implement custom functions and modules on top of forked code.
/// Example: Staking systems. Very common in DeFi. Re-investing/Re-Staking rewards on the Vault level can be included in permissionless way.
contract CompoundV3ERC4626Wrapper is ERC4626 {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using LibCompound for CometMainInterface;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when a call to Compound returned an error.
    /// @param errorCode The error code returned by Compound
    error CompoundERC4626__CompoundError(uint256 errorCode);

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant NO_ERROR = 0;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice The COMP-like token contract
    ERC20 public immutable reward;

    /// @notice The Compound cToken contract
    CometMainInterface public immutable cToken;

    /// @notice The Compound comptroller contract
    ICometRewards public immutable comptroller;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    address[] public rewards;

    /// Compact struct to make two swaps (PancakeSwap on BSC)
    /// A => B (using pair1) then B => asset (of Wrapper) (using pair2)
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_, // underlying
        ERC20 reward_, // comp token or other
        CometMainInterface cToken_, // compound concept of a share
        ICometRewards comptroller_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        reward = reward_;
        cToken = cToken_;
        comptroller = comptroller_;
        manager = manager_;
    }

    /// -----------------------------------------------------------------------
    /// Compound liquidity mining
    /// -----------------------------------------------------------------------

    function setRoute(
        address token,
        address pair1,
        address pair2, 
        uint256 index
    ) external {
        require(msg.sender == manager, "onlyOwner");
        SwapInfo = swapInfo(token, pair1, pair2);
        ERC20(rewards[index]).approve(SwapInfo.pair1, type(uint256).max); /// max approve
        ERC20(SwapInfo.token).approve(SwapInfo.pair2, type(uint256).max); /// max approve
    }

    function addReward(address reward_) external {
        require(msg.sender == manager, "onlyOwner");
        rewards.push(reward_);
    }

    /// @notice Claims liquidity mining rewards from Compound and performs low-lvl swap with instant reinvesting
    /// Calling harvest() claims COMP-Fork token through direct Pair swap for best control and lowest cost
    /// harvest() can be called by anybody. ideally this function should be adjusted per needs (e.g add fee for harvesting)
    function harvest() external {

        comptroller.claim(address(cToken), address(this), true);

        for (uint256 index = 0; index < rewards.length; index++) {
            address rewardToken = address(rewards[index]);
            uint256 earned = ERC20(rewardToken).balanceOf(address(this));
            

            /// If only one swap needed (high liquidity pair) - set swapInfo.token0/token/pair2 to 0x
            if (SwapInfo.token == address(asset)) {
                DexSwap.swap(
                    earned, /// REWARDS amount to swap
                    rewardToken, // from REWARD (because of liquidity)
                    address(asset), /// to target underlying of this Vault ie USDC
                    SwapInfo.pair1 /// pairToken (pool)
                );
            /// If two swaps needed
            } else {
                uint256 swapTokenAmount = DexSwap.swap(
                    earned, /// REWARDS amount to swap
                    rewardToken, /// fromToken REWARD
                    SwapInfo.token, /// to intermediary token with high liquidity (no direct pools)
                    SwapInfo.pair1 /// pairToken (pool)
                );

                DexSwap.swap(
                    swapTokenAmount,
                    SwapInfo.token, // from received BUSD (because of liquidity)
                    address(asset), /// to target underlying of this Vault ie USDC
                    SwapInfo.pair2 /// pairToken (pool)
                );
            }
        }

        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// We can't inherit directly from Yield-daddy because of rewardClaim lock
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return cToken.balanceOf(address(this));
    }
    
    function beforeWithdraw(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Compound
        /// -----------------------------------------------------------------------

        cToken.withdraw(address(asset), assets);
        // if (errorCode != NO_ERROR) {
        //     revert CompoundERC4626__CompoundError(errorCode);
        // }
    }

    function afterDeposit(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Deposit assets into Compound
        /// -----------------------------------------------------------------------

        // approve to cToken
        asset.safeApprove(address(cToken), assets);

        // deposit into cToken
        cToken.supply(address(asset), assets);
        // if (errorCode != NO_ERROR) {
        //     revert CompoundERC4626__CompoundError(errorCode);
        // }
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (cToken.isSupplyPaused()) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (cToken.isSupplyPaused()) return 0;
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        // uint256 cash = cToken.getCash();
        if (cToken.isWithdrawPaused()) return 0;
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return assetsBalance;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        // uint256 cash = cToken.getCash();
        // uint256 cashInShares = convertToShares(cash);
        if (cToken.isWithdrawPaused()) return 0;
        uint256 shareBalance = balanceOf[owner];
        return shareBalance;
    }

    /// -----------------------------------------------------------------------
    /// ERC20 metadata generation
    /// -----------------------------------------------------------------------

    function _vaultName(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultName)
    {
        vaultName = string.concat("CompStratERC4626- ", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("cS-", asset_.symbol());
    }
}
