// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IBToken} from "./interfaces/IBToken.sol";
import {IFairLaunch} from "./interfaces/IFairLaunch.sol";
import {IVaultConfig} from "./interfaces/IVaultConfig.sol";
import {DexSwap} from "../_global/swapUtils.sol";

/// @title Alpaca ERC4626 Wrapper
/// @notice Extended AAVE-V2 logic using FairLaunch (and not AaveMining) for rewards distribution
/// @author ZeroPoint Labs
contract AlpacaERC4626Reinvest is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                      LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when reinvested amounts are not enough.
    error MIN_AMOUNT_ERROR();

    /// @notice Thrown when trying to redeem with 0 tokens invested
    error ZERO_ASSETS();

    /// @notice Thrown when trying to call a function with an invalid access
    error INVALID_ACCESS();

    /*//////////////////////////////////////////////////////////////
                      IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice CToken token reference
    IBToken public immutable ibToken;
    address public immutable manager;
    IFairLaunch public immutable staking;
    address public immutable alpacaToken;
    ERC20 public immutable rewardToken;

    uint256 public poolId;

    /// @notice Pointer to swapInfo
    swapInfo public SwapInfo;

    /// Compact struct to make two swaps (PancakeSwap on BSC)
    /// A => B (using pair1) then B => asset (of BaseWrapper) (using pair2)
    /// will work fine as long we only get 1 type of reward token
    struct swapInfo {
        address token;
        address pair1;
        address pair2;
    }

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice AlpacaERC4626Reinvest constructor
    /// @param asset_ The address of the ibToken
    /// @param staking_ The address of the reward pool
    /// @param poolId_ The poolId of the ibToken
    constructor(
        IBToken asset_, // ibToken
        IFairLaunch staking_, // reward pool
        uint256 poolId_ // individual ibToken poolId
    )
        ERC4626(
            ERC20(asset_.token()), // underlying Vault asset out of ibToken
            _vaultName(ERC20(asset_.token())),
            _vaultSymbol(ERC20(asset_.token()))
        )
    {
        ibToken = asset_;
        staking = staking_;
        poolId = poolId_;
        alpacaToken = staking.alpaca();
        rewardToken = ERC20(staking.alpaca());
        manager = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 underlyingAmount_, uint256) internal override {
        // convert asset token amount to ibtokens for withdrawal
        uint256 sharesToWithdraw =
            underlyingAmount_.mulDivDown(ERC20(address(ibToken)).totalSupply(), alpacaVaultTotalToken());

        // Withdraw the underlying tokens from the cToken.
        _unstake(sharesToWithdraw);
        ibToken.withdraw(sharesToWithdraw);
    }

    function afterDeposit(uint256 underlyingAmount_, uint256) internal override {
        asset.safeApprove(address(ibToken), underlyingAmount_);

        ibToken.deposit(underlyingAmount_);

        /// WARN: balanceOf(address(this))
        ibToken.approve(address(staking), ibToken.balanceOf(address(this)));

        staking.deposit(address(this), poolId, ERC20(address(ibToken)).balanceOf(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                          REWARDS LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Set swap routes for selling rewards
    function setRoute(address token_, address pair1_, address pair2_) external {
        if (msg.sender != manager) revert INVALID_ACCESS();
        SwapInfo = swapInfo(token_, pair1_, pair2_);
    }

    /// @notice Harvest AlpacaToken rewards for all of the shares held by this vault
    /// @notice Amount gets reinvested into the vault after swap to the underlying
    /// @notice This implementation is sub-optimal for fair distribution of APY among shareholders
    /// @notice Ie. Shareholder may request to withdraw his share before harvest accrued value, forfeiting his rewards
    /// boosted APY
    function harvest(uint256 minAmountOut_) external {
        staking.harvest(poolId);

        uint256 earned = ERC20(alpacaToken).balanceOf(address(this));
        uint256 reinvestAmount;

        /// For ALPACA we use best liquidity pairs on Pancakeswap
        /// https://pancakeswap.finance/info/pools
        /// Only one swap needed, in this case - set swapInfo.token0/token/pair2 to 0x
        if (SwapInfo.token == address(asset)) {
            rewardToken.approve(SwapInfo.pair1, earned);

            reinvestAmount = DexSwap.swap(
                earned,
                /// ALPACA amount to swap
                alpacaToken, // from ALPACA (because of liquidity)
                address(asset),
                /// to target underlying of BaseWrapper ie USDC
                SwapInfo.pair1
            );
            /// pairToken (pool)
            /// https://pancakeswap.finance/info/pool/0x2354ef4df11afacb85a5c7f98b624072eccddbb1

            /// Two swaps needed
        } else {
            rewardToken.approve(SwapInfo.pair1, earned);

            uint256 swapTokenAmount = DexSwap.swap(
                earned,
                /// ALPACA amount to swap
                alpacaToken,
                /// fromToken ALPACA
                SwapInfo.token,
                /// toToken ie BUSD (because of liquidity)
                SwapInfo.pair1
            );
            /// pairToken (pool)
            /// https://pancakeswap.finance/info/pool/0x7752e1fa9f3a2e860856458517008558deb989e3

            ERC20(SwapInfo.token).approve(SwapInfo.pair2, swapTokenAmount);

            reinvestAmount = DexSwap.swap(
                swapTokenAmount,
                SwapInfo.token, // from received BUSD (because of liquidity)
                address(asset),
                /// to target underlying of BaseWrapper USDC
                SwapInfo.pair2
            );
            /// pairToken (pool)
            /// https://pancakeswap.finance/info/pool/0x2354ef4df11afacb85a5c7f98b624072eccddbb1
        }
        if (reinvestAmount < minAmountOut_) {
            revert MIN_AMOUNT_ERROR();
        }

        afterDeposit(asset.balanceOf(address(this)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function withdraw(uint256 assets_, address receiver_, address owner_) public override returns (uint256 shares) {
        shares = previewWithdraw(assets_); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares;
            }
        }

        beforeWithdraw(assets_, shares);

        _burn(owner_, shares);

        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        /// WARN: balanceOf(address(this))
        asset.safeTransfer(receiver_, asset.balanceOf(address(this)));
    }

    function redeem(uint256 shares_, address receiver_, address owner_) public override returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares_;
            }
        }

        // Check for rounding error since we round down in previewRedeem.
        if ((assets = previewRedeem(shares_)) == 0) revert ZERO_ASSETS();

        beforeWithdraw(assets, shares_);

        _burn(owner_, shares_);

        emit Withdraw(msg.sender, receiver_, owner_, asset.balanceOf(address(this)), shares_);

        /// WARN: balanceOf(address(this))
        asset.safeTransfer(receiver_, asset.balanceOf(address(this)));
    }

    function _unstake(uint256 ibTokenAmount_) internal {
        staking.withdraw(address(this), poolId, ibTokenAmount_);
    }

    function _viewUnderlyingBalanceOf() internal view returns (uint256) {
        IFairLaunch._userInfo memory depositDetails = staking.userInfo(poolId, address(this));
        return depositDetails.amount.mulDivUp(alpacaVaultTotalToken(), ERC20(address(ibToken)).totalSupply());
    }

    function alpacaVaultTotalToken() public view returns (uint256) {
        uint256 reservePool = ibToken.reservePool();
        uint256 vaultDebtVal = ibToken.vaultDebtVal();
        if (block.timestamp > ibToken.lastAccrueTime()) {
            uint256 interest = ibToken.pendingInterest(0);
            uint256 toReserve = interest.mulDivDown(IVaultConfig(ibToken.config()).getReservePoolBps(), 10_000);
            reservePool = reservePool + (toReserve);
            vaultDebtVal = vaultDebtVal + (interest);
        }
        return asset.balanceOf(address(ibToken)) + (vaultDebtVal) - (reservePool);
    }

    /// @notice AUM of the Vault (ibToken balance)
    /// @dev This implementation doesn't always refelcts the actual AUM (pre-harvest())
    function totalAssets() public view override returns (uint256) {
        return _viewUnderlyingBalanceOf();
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 METADATA GENERATION
    //////////////////////////////////////////////////////////////*/

    function _vaultName(ERC20 asset_) internal view virtual returns (string memory vaultName) {
        vaultName = string.concat("ERC4626-Wrapped Alpaca-", asset_.symbol());
    }

    function _vaultSymbol(ERC20 asset_) internal view virtual returns (string memory vaultSymbol) {
        vaultSymbol = string.concat("alp4626-", asset_.symbol());
    }
}
