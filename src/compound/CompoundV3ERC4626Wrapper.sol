// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {CometMainInterface} from "./compound/IComet.sol";
import {LibCompound} from "./compound/LibCompound.sol";
import {ICometRewards} from "./compound/ICometRewards.sol";
import {ISwapRouter} from "../aave-v2/utils/ISwapRouter.sol";
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

    /// @notice Thrown when reinvest amount is not enough.
    error MIN_AMOUNT_ERROR();
    /// @notice Thrown when caller is not the manager.
    error INVALID_ACCESS_ERROR();
    /// @notice Thrown when swap path fee in reinvest is invalid.
    error INVALID_FEE_ERROR();

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant NO_ERROR = 0;
    /// @notice Pointer to swapInfo
    bytes public swapPath;

    ERC20 public immutable reward;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice The Compound cToken contract
    CometMainInterface public immutable cToken;

    /// @notice The Compound rewards manager contract
    ICometRewards public immutable rewardsManager;

    ISwapRouter public immutable swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        ERC20 asset_, // underlying
        CometMainInterface cToken_, // compound concept of a share
        ICometRewards rewardsManager_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        cToken = cToken_;
        rewardsManager = rewardsManager_;
        manager = manager_;
        (address reward_, ,) = rewardsManager.rewardConfig(address(cToken));
        reward = ERC20(reward_);
    }

    /// -----------------------------------------------------------------------
    /// Compound liquidity mining
    /// -----------------------------------------------------------------------

    function setRoute(
        uint24 poolFee1_,
        address tokenMid_,
        uint24 poolFee2_
    ) external {
        if(msg.sender != manager)
            revert INVALID_ACCESS_ERROR();
        if(poolFee1_ == 0)
            revert INVALID_FEE_ERROR();
        if(poolFee2_ == 0 || tokenMid_ == address(0))
            swapPath  = abi.encodePacked(reward, poolFee1_, address(asset));
        else 
            swapPath  = abi.encodePacked(reward, poolFee1_, tokenMid_, poolFee2_, address(asset));
        ERC20(reward).approve(address(swapRouter), type(uint256).max); /// max approve
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
    }

    function harvest(uint256 minAmountOut_) external {
        rewardsManager.claim(address(cToken), address(this), true);

        uint256 earned = ERC20(reward).balanceOf(address(this));
        uint256 reinvestAmount;
        /// @dev Swap rewards to asset
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: swapPath,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: earned,
                amountOutMinimum: minAmountOut_
            });

        // Executes the swap.
        reinvestAmount = swapRouter.exactInput(params);
        if(reinvestAmount < minAmountOut_) {
            revert MIN_AMOUNT_ERROR();
        }
        afterDeposit(asset.balanceOf(address(this)), 0);
        
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