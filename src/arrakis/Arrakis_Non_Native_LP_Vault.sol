// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IGUniPool} from "./utils/IGUniPool.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "./utils/TickMath.sol";
import {LiquidityAmounts, FullMath} from "./utils/LiquidityAmounts.sol";
import {IArrakisRouter} from "./interfaces/IArrakisRouter.sol";
import {IGauge} from "./interfaces/IGauge.sol";

/// @title ArrakisNonNativeVault
/// @notice A vault for wrapping arrakis vault LP tokens and depositing them to the vault.
/// @notice Deposited asset get swapped partially to the non_asset and then deposited to the arrakis vault for an LP.
/// @author ZeroPoint Labs
contract ArrakisNonNativeVault is ERC4626 {
    /*//////////////////////////////////////////////////////////////
                      LIBRARIES USAGE
    //////////////////////////////////////////////////////////////*/
    using SafeTransferLib for *;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    using TickMath for int24;

    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when trying to redeem with 0 tokens invested
    error ZERO_ASSETS();

    /// @notice Thrown when univ3 callback is not being made by the pool
    error NOT_UNIV3_POOL_CALLBACK();

    /*//////////////////////////////////////////////////////////////
                      IMMUTABLES & VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice arrakis vault
    IGUniPool public immutable arrakisVault;
    /// @notice zeroForOne is true if token0 is the asset, else token1 is the asset
    bool zeroForOne;

    IArrakisRouter public arrakisRouter;
    /// @notice gauge is the contract which gives staking Rewards
    IGauge public gauge;

    uint160 X96 = 2**96;

    uint160 slippage;
    /// @notice non_asset is the token which is not the asset in a univ3 pool
    ERC20 public non_asset;

    struct swapParams {
        address receiver;
        bool direction;
        int256 amount;
        uint160 sqrtPrice;
        bytes data;
    }

    /*//////////////////////////////////////////////////////////////
                      CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice ArrakisNonNativeVault constructor
    /// @param gUniPool_ Compound cToken to wrap
    /// @param name_ ERC20 name of the vault shares token
    /// @param symbol_ ERC20 symbol of the vault shares token
    /// @param isToken0_ if true, token0 in the pool is the asset, else token1 is the asset
    /// @param arrakisRouter_ the arrakis router contract
    /// @param gauge_ the contract which gives staking Rewards
    /// @param slippage_ 50 would give you 2% slippage which  means sqrtPrice +/- 2 tickSpaces
    constructor(
        address gUniPool_,
        string memory name_,
        string memory symbol_,
        bool isToken0_,
        address arrakisRouter_,
        address gauge_,
        uint160 slippage_
    )
        ERC4626(
            ERC20(
                isToken0_
                    ? address(IGUniPool(gUniPool_).token0())
                    : address(IGUniPool(gUniPool_).token1())
            ),
            name_,
            symbol_
        )
    {
        arrakisVault = IGUniPool(gUniPool_);
        zeroForOne = isToken0_;
        arrakisRouter = IArrakisRouter(arrakisRouter_);
        gauge = IGauge(gauge_);
        slippage = slippage_;
        non_asset = zeroForOne ? arrakisVault.token1() : arrakisVault.token0();
        /// @dev doing it one time instead of each and every deposit/withdrawal swaps
        _approveTokenIfNeeded(address(asset), address(arrakisRouter));
        _approveTokenIfNeeded(address(non_asset), address(arrakisRouter));
        _approveTokenIfNeeded(address(non_asset), address(arrakisVault.pool()));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 underlyingLiquidity_, uint256)
        internal
        override
    {
        /// @notice getting the pool liquidity from arrakis vault
        IUniswapV3Pool uniPool = arrakisVault.pool();
        (uint128 liquidity_, , , , ) = uniPool.positions(
            arrakisVault.getPositionID()
        );
        uint256 sharesToWithdraw = (underlyingLiquidity_ *
            arrakisVault.totalSupply()) / liquidity_;
        /// @notice withdraw from staking contract
        gauge.withdraw(sharesToWithdraw);
        /// @notice burn arrakis lp
        arrakisVault.burn(sharesToWithdraw, address(this));

        uint256 nonAssetBal = non_asset.balanceOf(address(this));
        (uint160 sqrtPriceX96, , , , , , ) = uniPool.slot0();
        uint160 twoPercentSqrtPrice = sqrtPriceX96 / slippage;
        /// @notice calculating slippage for 2% +/- the current tick of the uniPool for swapping
        swapParams memory params = swapParams({
            receiver: address(this),
            direction: !zeroForOne,
            amount: int256(nonAssetBal),
            sqrtPrice: !zeroForOne
                ? sqrtPriceX96 - (twoPercentSqrtPrice)
                : sqrtPriceX96 + (twoPercentSqrtPrice),
            data: ""
        });
        /// @notice swap the non_asset total amount to withdrawable asset
        _swap(params);
    }

    /// Underlying balance of the assets (notional value in terms of asset) this contract holds.
    function _viewUnderlyingBalanceOf() internal view returns (uint256) {
        (uint256 gross0, uint256 gross1) = _getUnderlyingOrLiquidity(
            arrakisVault
        );
        (uint160 sqrtRatioX96, , , , , , ) = arrakisVault.pool().slot0();
        uint256 priceDecimals;
        uint256 liquidity;
        uint256 grossLiquidity;
        /// @dev calculating non_asset price in terms on asset price to find virtual total assets in terms of deposit asset
        if (zeroForOne) {
            /// @dev using sqrtPriceX96 * sqrtPriceX96 to calculate the price of non_asset in terms of asset
            priceDecimals = (((10**non_asset.decimals()) * X96) /
                ((sqrtRatioX96 * sqrtRatioX96) / X96));
            grossLiquidity = ((((priceDecimals) *
                ((gross1 * (10**asset.decimals())) /
                    (10**non_asset.decimals()))) / (10**asset.decimals())) +
                gross0);
            liquidity =
                (grossLiquidity * gauge.balanceOf(address(this))) /
                arrakisVault.totalSupply();
        } else {
            priceDecimals =
                ((10**non_asset.decimals()) *
                    ((sqrtRatioX96 * sqrtRatioX96) / X96)) /
                X96;
            grossLiquidity = (((priceDecimals) *
                ((gross0 * (10**asset.decimals())) /
                    (10**non_asset.decimals()))) /
                (10**asset.decimals()) +
                gross1);
            liquidity =
                (grossLiquidity * gauge.balanceOf(address(this))) /
                arrakisVault.totalSupply();
        }
        return liquidity;
    }

    function afterDeposit(uint256 underlyingAmount_, uint256)
        internal
        override
    {
        (uint160 sqrtRatioX96, , , , , , ) = arrakisVault.pool().slot0();
        uint256 priceDecimals = (1 ether *
            ((sqrtRatioX96 * sqrtRatioX96) / X96)) / X96;

        /// @dev multiplying the price decimals by 1e12 as the price you get from sqrtRationX96 is 6 decimals but need 18 decimal value for this method
        (bool _direction, uint256 swapAmount) = getRebalanceParams(
            arrakisVault,
            zeroForOne ? underlyingAmount_ : 0,
            !zeroForOne ? underlyingAmount_ : 0,
            priceDecimals * 1e12
        );

        uint160 twoPercentSqrtPrice = sqrtRatioX96 / slippage;
        uint160 lowerLimit = sqrtRatioX96 - (twoPercentSqrtPrice);
        uint160 upperLimit = sqrtRatioX96 + (twoPercentSqrtPrice);

        swapParams memory params = swapParams({
            receiver: address(this),
            direction: _direction,
            amount: int256(swapAmount),
            sqrtPrice: zeroForOne ? lowerLimit : upperLimit,
            data: ""
        });

        _swap(params);

        /// @notice we need a final swap to put the remaining amount of tokens into liquidity as before swap might have moved the liquidity positions needed.
        uint256 token0Bal = arrakisVault.token0().balanceOf(address(this));
        uint256 token1Bal = arrakisVault.token1().balanceOf(address(this));
        (uint256 amount0Used, uint256 amount1Used, ) = arrakisVault
            .getMintAmounts(token0Bal, token1Bal);
        arrakisRouter.addLiquidityAndStake(
            gauge,
            token0Bal,
            token1Bal,
            amount0Used,
            amount1Used,
            address(this)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ERC4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public override returns (uint256 assets) {
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; /// @dev Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares_;
        }
        uint256 liquidity;
        /// @dev Check for rounding error since we round down in previewRedeem.
        if ((liquidity = previewRedeem(shares_)) == 0) revert ZERO_ASSETS();

        beforeWithdraw(liquidity, shares_);

        _burn(owner_, shares_);
        assets = asset.balanceOf(address(this));
        emit Withdraw(msg.sender, receiver_, owner_, assets, shares_);

        asset.safeTransfer(receiver_, assets);
    }

    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public override returns (uint256 shares) {
        uint256 liquidity = previewWithdraw(assets_); /// @dev No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; /// @dev Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner_][msg.sender] = allowed - shares;
        }
        shares = liquidity.mulDivDown(totalSupply, totalLiquidity());
        beforeWithdraw(liquidity, shares);

        _burn(owner_, shares);

        assets_ = asset.balanceOf(address(this));
        emit Withdraw(msg.sender, receiver_, owner_, assets_, shares);

        asset.safeTransfer(receiver_, assets_);
    }

    function totalLiquidity() public view returns (uint256) {
        (uint128 liquidity_, , , , ) = arrakisVault.pool().positions(
            arrakisVault.getPositionID()
        );
        uint256 liquidity = (gauge.balanceOf(address(this)) * liquidity_) /
            arrakisVault.totalSupply();
        return liquidity;
    }

    /// @notice returns the liquidity on uniswap that can be redeemable
    function previewRedeem(uint256 shares_)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply; /// @dev Saves an extra SLOAD if totalSupply is non-zero.

        return
            supply == 0
                ? shares_
                : shares_.mulDivDown(totalLiquidity(), supply);
    }

    /// @notice returns the liquidity on uniswap thats withdrawn to get desired assets
    function previewWithdraw(uint256 assets_)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply; /// @dev Saves an extra SLOAD if totalSupply is non-zero.

        return
            supply == 0
                ? assets_
                : assets_.mulDivUp(totalLiquidity(), totalAssets());
    }

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return _viewUnderlyingBalanceOf();
    }

    /*//////////////////////////////////////////////////////////////
                            LIMITS
    //////////////////////////////////////////////////////////////*/

    /// @notice maximum amount of assets that can be deposited.
    function maxDeposit(address) public view override returns (uint256) {
        if (arrakisVault.restrictedMintToggle() == 11111) return 0;
        return type(uint256).max;
    }

    /// @notice maximum amount of shares that can be minted.
    function maxMint(address) public view override returns (uint256) {
        if (arrakisVault.restrictedMintToggle() == 11111) return 0;
        return type(uint256).max;
    }

    /// @notice Maximum amount of liquidity of the pool that can be withdrawn.
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (arrakisVault.restrictedMintToggle() == 11111) return 0;
        uint256 liquidityBalance = convertToAssets(balanceOf[owner]);
        return liquidityBalance;
    }

    /// @notice Maximum amount of shares that can be redeemed.
    function maxRedeem(address owner) public view override returns (uint256) {
        if (arrakisVault.restrictedMintToggle() == 11111) return 0;
        return ERC20(address(this)).balanceOf(owner);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                            UTILITIES METHODS
    //////////////////////////////////////////////////////////////*/

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta_,
        int256 amount1Delta_,
        bytes calldata /*data*/
    ) external {
        if (msg.sender != address(arrakisVault.pool()))
            revert NOT_UNIV3_POOL_CALLBACK();

        if (amount0Delta_ > 0)
            ERC20(address(arrakisVault.token0())).safeTransfer(
                msg.sender,
                uint256(amount0Delta_)
            );
        else if (amount1Delta_ > 0)
            ERC20(address(arrakisVault.token1())).safeTransfer(
                msg.sender,
                uint256(amount1Delta_)
            );
    }

    /**
     * @dev allows calling approve for a token to a specific spender
     * @notice this is an internal function. only used to give approval of
     * @notice the funds in this contract to other contracts
     * @param token_ the token to give approval for
     * @param spender_ the spender of the token
     */
    function _approveTokenIfNeeded(address token_, address spender_) private {
        if (ERC20(token_).allowance(address(this), spender_) == 0) {
            ERC20(token_).safeApprove(spender_, type(uint256).max);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP LOGIC HELPERS
    //////////////////////////////////////////////////////////////*/

    function getRebalanceParams(
        IGUniPool pool_,
        uint256 amount0In_,
        uint256 amount1In_,
        uint256 price18Decimals_
    ) public view returns (bool direction, uint256 swapAmount) {
        uint256 amount0Left;
        uint256 amount1Left;
        try pool_.getMintAmounts(amount0In_, amount1In_) returns (
            uint256 amount0,
            uint256 amount1,
            uint256
        ) {
            amount0Left = amount0In_ - amount0;
            amount1Left = amount1In_ - amount1;
        } catch {
            amount0Left = amount0In_;
            amount1Left = amount1In_;
        }

        (uint256 gross0, uint256 gross1) = _getUnderlyingOrLiquidity(pool_);

        if (gross1 == 0) {
            return (false, amount1Left);
        }

        if (gross0 == 0) {
            return (true, amount0Left);
        }

        uint256 factor0 = 10**(18 - ERC20(address(pool_.token0())).decimals());
        uint256 factor1 = 10**(18 - ERC20(address(pool_.token1())).decimals());
        uint256 weightX18 = FullMath.mulDiv(
            gross0 * factor0,
            1 ether,
            gross1 * factor1
        );
        uint256 proportionX18 = FullMath.mulDiv(
            weightX18,
            price18Decimals_,
            1 ether
        );
        uint256 factorX18 = FullMath.mulDiv(
            proportionX18,
            1 ether,
            proportionX18 + 1 ether
        );

        if (amount0Left > amount1Left) {
            direction = true;
            swapAmount = FullMath.mulDiv(
                amount0Left,
                1 ether - factorX18,
                1 ether
            );
        } else if (amount1Left > amount0Left) {
            swapAmount = FullMath.mulDiv(amount1Left, factorX18, 1 ether);
        }
    }

    function _getUnderlyingOrLiquidity(IGUniPool pool_)
        internal
        view
        returns (uint256 gross0, uint256 gross1)
    {
        (gross0, gross1) = pool_.getUnderlyingBalances();
        if (gross0 == 0 && gross1 == 0) {
            IUniswapV3Pool uniPool = pool_.pool();
            (uint160 sqrtPriceX96, , , , , , ) = uniPool.slot0();
            uint160 lowerSqrtPrice = pool_.lowerTick().getSqrtRatioAtTick();
            uint160 upperSqrtPrice = pool_.upperTick().getSqrtRatioAtTick();
            (gross0, gross1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                lowerSqrtPrice,
                upperSqrtPrice,
                1 ether
            );
        }
    }

    function _swap(swapParams memory params_) internal {
        IUniswapV3Pool uniPool = arrakisVault.pool();
        uniPool.swap(
            params_.receiver,
            params_.direction,
            params_.amount,
            params_.sqrtPrice,
            params_.data
        );
    }
}
