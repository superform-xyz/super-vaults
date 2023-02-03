// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ICERC20} from "./compound/ICERC20.sol";
import {LibCompound} from "./compound/LibCompound.sol";
import {IComptroller} from "./compound/IComptroller.sol";

import {DexSwap} from "./utils/swapUtils.sol";

/// @title BenqiERC4626Reinvest - Custom implementation of yield-daddy wrappers with flexible reinvesting logic
contract BenqiERC4626Reinvest is ERC4626 {
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

    error NotEnoughReinvestAmount_Error();

    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------

    uint256 internal constant NO_ERROR = 0;

    /// -----------------------------------------------------------------------
    /// Immutable params
    /// -----------------------------------------------------------------------

    /// @notice Access Control for harvest() route
    address public immutable manager;

    /// @notice Type of reward currently distributed by Benqi Vaults
    uint8 public rewardType;

    /// @notice Map rewardType to rewardToken
    mapping(uint8 => address) public rewardTokenMap;

    /// @notice Map rewardType to swap route
    mapping(uint8 => swapInfo) public swapInfoMap;

    /// @notice The Compound cToken contract
    ICERC20 public immutable cToken;

    /// @notice The Compound comptroller contract
    IComptroller public immutable comptroller;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

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
        ERC20 asset_,
        ICERC20 cToken_,
        IComptroller comptroller_,
        address manager_
    ) ERC4626(asset_, _vaultName(asset_), _vaultSymbol(asset_)) {
        cToken = cToken_;
        comptroller = comptroller_;
        manager = manager_;
    }

    /// -----------------------------------------------------------------------
    /// Compound liquidity mining
    /// -----------------------------------------------------------------------

    /// @notice Set swap routes for selling rewards
    /// @notice Set type of reward we are harvesting and selling
    /// @dev 0 = BenqiToken, 1 = AVAX
    /// @dev Setting wrong addresses here will revert harvest() calls
    function setRoute(
        uint8 rewardType_,
        address rewardToken,
        address token,
        address pair1,
        address pair2
    ) external {
        require(msg.sender == manager, "onlyOwner");
        swapInfoMap[rewardType_] = swapInfo(token, pair1, pair2);
        rewardTokenMap[rewardType_] = rewardToken;
    }


    /// @notice Claims liquidity mining rewards from Benqi and sends it to this Vault
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
                earned, /// REWARDS amount to swap
                rewardToken, // from REWARD (because of liquidity)
                address(asset), /// to target underlying of this Vault ie USDC
                swapMap.pair1 /// pairToken (pool)
            );
            /// If two swaps needed
        } else {

            rewardToken_.approve(swapMap.pair1, earned);

            uint256 swapTokenAmount = DexSwap.swap(
                earned, /// REWARDS amount to swap
                rewardToken, /// fromToken REWARD
                swapMap.token, /// to intermediary token with high liquidity (no direct pools)
                swapMap.pair1 /// pairToken (pool)
            );

            ERC20(swapMap.token).approve(swapMap.pair2, swapTokenAmount); 

            reinvestAmount = DexSwap.swap(
                swapTokenAmount,
                swapMap.token, // from received BUSD (because of liquidity)
                address(asset), /// to target underlying of this Vault ie USDC
                swapMap.pair2 /// pairToken (pool)
            );
        }
        if(reinvestAmount < minAmountOut_)
            revert NotEnoughReinvestAmount_Error();
        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /// @notice Check how much rewards are available to claim, useful before harvest()
    function getRewardsAccrued(uint8 rewardType_) external view returns (uint256 amount) {
        amount = comptroller.rewardAccrued(rewardType_, address(this));
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// We can't inherit directly from Yield-daddy because of rewardClaim lock
    /// -----------------------------------------------------------------------

    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        return
            cToken.balanceOf(address(this)).mulWadDown(
                cToken.exchangeRateStored()
            );
    }

    function totalAssets() public view virtual override returns (uint256) {
        /// TODO: Investigate why libcompound fails for benqi fork?
        return viewUnderlyingBalanceOf();
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
        if (comptroller.mintGuardianPaused(address(cToken))) return 0;
        return type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        if (comptroller.mintGuardianPaused(address(cToken))) return 0;
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
        vaultName = string.concat("ERC4626-Wrapped Benqi-", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_)
        internal
        view
        virtual
        returns (string memory vaultSymbol)
    {
        vaultSymbol = string.concat("bq46-", asset_.symbol());
    }
}
