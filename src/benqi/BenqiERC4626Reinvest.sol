// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { IBERC20 } from "./external/IBERC20.sol";
import { LibBCompound } from "./external/LibBCompound.sol";
import { IBComptroller } from "./external/IBComptroller.sol";

import { DexSwap } from "../_global/swapUtils.sol";

/// @title BenqiERC4626Reinvest
/// @notice Custom implementation of yield-daddy Compound wrapper with flexible reinvesting logic
/// @author ZeroPoint Labs
contract BenqiERC4626Reinvest is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                        LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/

    using LibBCompound for IBERC20;
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when a call to Compound returned an error.
    /// @param errorCode The error code returned by Compound
    error COMPOUND_ERROR(uint256 errorCode);

    /// @notice Thrown when reinvested amounts are not enough.
    error MIN_AMOUNT_ERROR();

    /// @notice Thrown when trying to call a function with an invalid access
    error INVALID_ACCESS();

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant NO_ERROR = 0;

    /*//////////////////////////////////////////////////////////////
                      IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice Type of reward currently distributed by Benqi Vaults
    uint8 public rewardType;

    /// @notice Map rewardType to rewardToken
    mapping(uint8 => address) public rewardTokenMap;

    /// @notice Map rewardType to swap route
    mapping(uint8 => swapInfo) public swapInfoMap;

    /// @notice The Compound cToken contract
    IBERC20 public immutable cToken;

    /// @notice The Compound comptroller contract
    IBComptroller public immutable comptroller;

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

    /// @notice Constructs the BenqiERC4626Reinvest contract
    /// @dev asset_ is the underlying token of the Vault
    /// @dev cToken_ is the Compound cToken contract
    /// @dev comptroller_ is the Compound comptroller contract
    /// @dev manager_ is the address that can set swap routes
    constructor(
        ERC20 asset_,
        IBERC20 cToken_,
        IBComptroller comptroller_,
        address manager_
    )
        ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_))
    {
        cToken = cToken_;
        comptroller = comptroller_;
        manager = manager_;
    }

    /*//////////////////////////////////////////////////////////////
                        COMPOUND LIQUIDITY MINING
    //////////////////////////////////////////////////////////////*/

    /// @notice Set swap routes for selling rewards
    /// @notice Set type of reward we are harvesting and selling
    /// @dev 0 = BenqiToken, 1 = AVAX
    /// @dev Setting wrong addresses here will revert harvest() calls
    function setRoute(
        uint8 rewardType_,
        address rewardToken_,
        address token_,
        address pair1_,
        address pair2_
    )
        external
    {
        if (msg.sender != manager) revert INVALID_ACCESS();
        swapInfoMap[rewardType_] = swapInfo(token_, pair1_, pair2_);
        rewardTokenMap[rewardType_] = rewardToken_;
    }

    /// @notice Claims liquidity mining rewards from Benqi and sends it to this Vault
    /// @param rewardType_ Type of reward we are harvesting and selling
    /// @param minAmountOut_ Minimum amount of underlying asset to receive after harvest
    function harvest(uint8 rewardType_, uint256 minAmountOut_) external {
        swapInfo memory swapMap = swapInfoMap[rewardType_];
        address rewardToken = rewardTokenMap[rewardType_];
        ERC20 rewardToken_ = ERC20(rewardToken);

        comptroller.claimReward(rewardType_, address(this));
        uint256 earned = ERC20(rewardToken).balanceOf(address(this));
        uint256 reinvestAmount;
        /// If only one swap needed (high liquidity pair) - set swapInfo.token0/token/pair2 to 0x
        if (swapMap.token == address(asset)) {
            rewardToken_.approve(swapMap.pair1, earned);

            reinvestAmount = DexSwap.swap(
                earned,
                /// REWARDS amount to swap
                rewardToken, // from REWARD (because of liquidity)
                address(asset),
                /// to target underlying of this Vault ie USDC
                swapMap.pair1
            );
            /// pairToken (pool)
            /// If two swaps needed
        } else {
            rewardToken_.approve(swapMap.pair1, earned);

            uint256 swapTokenAmount = DexSwap.swap(
                earned,
                /// REWARDS amount to swap
                rewardToken,
                /// fromToken REWARD
                swapMap.token,
                /// to intermediary token with high liquidity (no direct pools)
                swapMap.pair1
            );
            /// pairToken (pool)

            ERC20(swapMap.token).approve(swapMap.pair2, swapTokenAmount);

            reinvestAmount = DexSwap.swap(
                swapTokenAmount,
                swapMap.token, // from received BUSD (because of liquidity)
                address(asset),
                /// to target underlying of this Vault ie USDC
                swapMap.pair2
            );
            /// pairToken (pool)
        }
        if (reinvestAmount < minAmountOut_) revert MIN_AMOUNT_ERROR();
        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /// @notice Check how much rewards are available to claim, useful before harvest()
    function getRewardsAccrued(uint8 rewardType_) external view returns (uint256 amount) {
        amount = comptroller.rewardAccrued(rewardType_, address(this));
    }

    /*//////////////////////////////////////////////////////////////
     ERC4626 overrides
     We can't inherit directly from Yield-daddy because of rewardClaim lock
    //////////////////////////////////////////////////////////////*/

    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        return cToken.balanceOf(address(this)).mulWadDown(cToken.exchangeRateStored());
    }

    function totalAssets() public view virtual override returns (uint256) {
        return viewUnderlyingBalanceOf();
    }

    function beforeWithdraw(uint256 assets_, uint256 /*shares*/ ) internal virtual override {
        /*//////////////////////////////////////////////////////////////
         Withdraw assets from Compound
        //////////////////////////////////////////////////////////////*/

        uint256 errorCode = cToken.redeemUnderlying(assets_);
        if (errorCode != NO_ERROR) {
            revert COMPOUND_ERROR(errorCode);
        }
    }

    function afterDeposit(uint256 assets_, uint256 /*shares*/ ) internal virtual override {
        /*//////////////////////////////////////////////////////////////
         Deposit assets into Compound
        //////////////////////////////////////////////////////////////*/

        // approve to cToken
        asset.safeApprove(address(cToken), assets_);

        // deposit into cToken
        uint256 errorCode = cToken.mint(assets_);
        if (errorCode != NO_ERROR) {
            revert COMPOUND_ERROR(errorCode);
        }
    }

    function maxDeposit(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(address(cToken))) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(address(cToken))) return 0;
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
                        ERC20 METADATA GENERATION
    //////////////////////////////////////////////////////////////*/

    function _vaultName(ERC20 asset_) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("ERC4626-Wrapped Benqi-", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("bq46-", asset_.symbol());
    }
}
