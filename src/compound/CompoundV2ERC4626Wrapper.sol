// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ICERC20} from "./compound/ICERC20.sol";
import {LibCompound} from "./compound/LibCompound.sol";
import {IComptroller} from "./compound/IComptroller.sol";
import {ISwapRouter} from "../aave-v2/utils/ISwapRouter.sol";
import {DexSwap} from "./utils/swapUtils.sol";
import "forge-std/console.sol";

/// @title CompoundV2StrategyWrapper - Custom implementation of yield-daddy wrappers with flexible reinvesting logic
/// Rationale: Forked protocols often implement custom functions and modules on top of forked code.
/// Example: Staking systems. Very common in DeFi. Re-investing/Re-Staking rewards on the Vault level can be included in permissionless way.
contract CompoundV2ERC4626Wrapper is ERC4626 {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using LibCompound for ICERC20;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------

    /// @notice Thrown when a call to Compound returned an error.
    /// @param errorCode The error code returned by Compound
    error CompoundERC4626__CompoundError(uint256 errorCode);
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

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice The COMP-like token contract
    ERC20 public immutable reward;

    /// @notice The Compound cToken contract
    ICERC20 public immutable cToken;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// @notice Pointer to swapInfo
    bytes public swapPath;

    ISwapRouter public immutable swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

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
        ICERC20 cToken_, // compound concept of a share
        IComptroller comptroller_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        reward = reward_;
        cToken = cToken_;
        comptroller = comptroller_;
        manager = manager_;
        ICERC20[] memory cTokens = new ICERC20[](1);
        cTokens[0] = cToken;
        comptroller.enterMarkets(cTokens);
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

    /// @notice Claims liquidity mining rewards from Compound and performs low-lvl swap with instant reinvesting
    /// Calling harvest() claims COMP-Fork token through direct Pair swap for best control and lowest cost
    /// harvest() can be called by anybody. ideally this function should be adjusted per needs (e.g add fee for harvesting)
    function harvest(uint256 minAmountOut_) external {
        ICERC20[] memory cTokens = new ICERC20[](1);
        cTokens[0] = cToken;
        comptroller.claimComp(address(this), cTokens);

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

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// We can't inherit directly from Yield-daddy because of rewardClaim lock
    /// -----------------------------------------------------------------------

    function totalAssets() public view virtual override returns (uint256) {
        return cToken.viewUnderlyingBalanceOf(address(this));
    }
    
    function beforeWithdraw(
        uint256 assets,
        uint256 /*shares*/
    ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Compound
        /// -----------------------------------------------------------------------

        uint256 errorCode = cToken.redeemUnderlying(assets);
        if (errorCode != NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
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
        uint256 errorCode = cToken.mint(assets);
        if (errorCode != NO_ERROR) {
            revert CompoundERC4626__CompoundError(errorCode);
        }
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(cToken)) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(cToken)) return 0;
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
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
