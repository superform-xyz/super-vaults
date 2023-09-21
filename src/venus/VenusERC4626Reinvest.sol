// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { IVERC20 } from "./external/IVERC20.sol";
import { LibVCompound } from "./external/LibVCompound.sol";
import { IVComptroller } from "./external/IVComptroller.sol";

import { DexSwap } from "../_global/swapUtils.sol";

/// @title VenusERC4626Reinvest
/// @notice Extended implementation of yield-daddy CompoundV2 wrapper
/// @notice Reinvests rewards accrued for higher APY
/// @author ZeroPoint Labs
contract VenusERC4626Reinvest is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                        LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/

    using LibVCompound for IVERC20;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a call to Compound returned an error.
    /// @param errorCode The error code returned by Compound
    error COMPOUND_ERROR(uint256 errorCode);

    /// @notice Thrown when reinvest amount is not enough.
    error MIN_AMOUNT_ERROR();

    /// @notice Thrown when trying to call a function with an invalid access
    error INVALID_ACCESS();

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant NO_ERROR = 0;

    /*//////////////////////////////////////////////////////////////
                      IMMUATABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice The COMP-like token contract
    ERC20 public immutable reward;

    /// @notice The Compound cToken contract
    IVERC20 public immutable cToken;

    /// @notice The Compound comptroller contract
    IVComptroller public immutable comptroller;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    /// Compact struct to make two swaps (PancakeSwap on BSC)
    /// A => B (using pair1) then B => asset (of Wrapper) (using pair2)
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructs this contract.
    /// @param asset_ The address of the asset to be wrapped
    /// @param reward_ The address of the reward token
    /// @param cToken_ The address of the cToken contract
    /// @param comptroller_ The address of the comptroller contract
    /// @param manager_ The address of the manager
    constructor(
        ERC20 asset_,
        ERC20 reward_,
        IVERC20 cToken_,
        IVComptroller comptroller_,
        address manager_
    )
        ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_))
    {
        reward = reward_;
        cToken = cToken_;
        comptroller = comptroller_;
        manager = manager_;
    }

    /*//////////////////////////////////////////////////////////////
                      VENUS LIQUIDITY MINING
    //////////////////////////////////////////////////////////////*/

    /// @notice Set swap route for XVS rewards
    function setRoute(address token_, address pair1_, address pair2_) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        SwapInfo = swapInfo(token_, pair1_, pair2_);
    }

    /// @notice Claims liquidity mining rewards from Compound and performs low-lvl swap with instant reinvesting
    function harvest(uint256 minAmountOut_) external {
        IVERC20[] memory cTokens = new IVERC20[](1);
        cTokens[0] = cToken;

        comptroller.claimVenus(address(this));

        uint256 earned = reward.balanceOf(address(this));

        address rewardToken = address(reward);
        uint256 reinvestAmount;

        /// XVS => WBNB => ASSET
        if (SwapInfo.token == address(asset)) {
            reward.approve(SwapInfo.pair1, earned);

            reinvestAmount = DexSwap.swap(
                earned,
                /// REWARDS amount to swap
                rewardToken, // from REWARD (because of liquidity)
                address(asset),
                /// to target underlying of this Vault ie USDC
                SwapInfo.pair1
            );
            /// pairToken (pool)
            /// If two swaps needed
        } else {
            reward.approve(SwapInfo.pair1, earned);

            uint256 swapTokenAmount = DexSwap.swap(
                earned,
                /// REWARDS amount to swap
                rewardToken,
                /// fromToken REWARD
                SwapInfo.token,
                /// to intermediary token with high liquidity (no direct pools)
                SwapInfo.pair1
            );
            /// pairToken (pool)

            ERC20(SwapInfo.token).approve(SwapInfo.pair2, swapTokenAmount);

            reinvestAmount = DexSwap.swap(
                swapTokenAmount,
                SwapInfo.token, // from received BUSD (because of liquidity)
                address(asset),
                /// to target underlying of this Vault ie USDC
                SwapInfo.pair2
            );
            /// pairToken (pool)
        }
        if (reinvestAmount < minAmountOut_) {
            revert MIN_AMOUNT_ERROR();
        }
        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /// @notice Check how much rewards are available to claim, useful before harvest()
    function getRewardsAccrued() external view returns (uint256 amount) {
        amount = comptroller.venusAccrued(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual override returns (uint256) {
        return cToken.viewUnderlyingBalanceOf(address(this));
    }

    function beforeWithdraw(uint256 assets_, uint256 /*shares*/ ) internal virtual override {
        /// @dev withdraw assets from venus

        uint256 errorCode = cToken.redeemUnderlying(assets_);
        if (errorCode != NO_ERROR) {
            revert COMPOUND_ERROR(errorCode);
        }
    }

    function afterDeposit(uint256 assets_, uint256 /*shares*/ ) internal virtual override {
        /// @dev deposit assets into venus

        // approve to cToken
        asset.safeApprove(address(cToken), assets_);

        // deposit into cToken
        uint256 errorCode = cToken.mint(assets_);
        if (errorCode != NO_ERROR) {
            revert COMPOUND_ERROR(errorCode);
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

    function maxWithdraw(address owner_) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 assetsBalance = convertToAssets(balanceOf[owner_]);
        return cash < assetsBalance ? cash : assetsBalance;
    }

    function maxRedeem(address owner_) public view override returns (uint256) {
        uint256 cash = cToken.getCash();
        uint256 cashInShares = convertToShares(cash);
        uint256 shareBalance = balanceOf[owner_];
        return cashInShares < shareBalance ? cashInShares : shareBalance;
    }

    /*//////////////////////////////////////////////////////////////
                            ERC20 METADATA
    //////////////////////////////////////////////////////////////*/

    function _vaultName(ERC20 asset_) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("ERC4626-Wrapped Venus-", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("vs46-", asset_.symbol());
    }
}
