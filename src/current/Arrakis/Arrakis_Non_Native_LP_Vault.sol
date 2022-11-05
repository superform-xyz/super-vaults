// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IGUniPool} from "../utils/arrakis/IGUniPool.sol";
import "forge-std/console.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "./utils/TickMath.sol";
import {LiquidityAmounts, FullMath} from "./utils/LiquidityAmounts.sol";


interface IGauge {
    function deposit(uint256 amount, address account) external;

    function withdraw(uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);

    // solhint-disable-next-line func-name-mixedcase
    function claim_rewards(address account) external;

    // solhint-disable-next-line func-name-mixedcase
    function staking_token() external returns (address);
}

interface IArrakisRouter {
    function mint(uint256 mintAmount, address receiver)
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidityMinted
        );

    function burn(uint256 burnAmount, address receiver)
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidityBurned
        );

    function getUnderlyingBalances()
        external
        view
        returns (uint256 amount0, uint256 amount1);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function addLiquidityAndStake(
        IGauge gauge,
        uint256 amount0Max,
        uint256 amount1Max,
        uint256 amount0Min,
        uint256 amount1Min,
        address receiver
    )
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint256 mintAmount
        );

    function removeLiquidityAndUnstake(
        IGauge gauge,
        uint256 burnAmount,
        uint256 amount0Min,
        uint256 amount1Min,
        address receiver
    )
        external
        returns (
            uint256 amount0,
            uint256 amount1,
            uint128 liquidityBurned
        );
}

contract ArrakisNonNativeVault is ERC4626 {
    using SafeTransferLib for *;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    using TickMath for int24;
    /// @notice CToken token reference
    IGUniPool public immutable arrakisVault;

    bool zeroForOne;

    IArrakisRouter public arrakisRouter;

    IGauge public gauge;

    bool blah; // used just for imitating swap , will be and can be removed in the next iteration

    uint160 X96 = 2**96;

    uint160 slippage;

    ERC20 non_asset;

    address private manager;

    struct swapParams {
        address receiver;
        bool direction;
        int256 amount;
        uint160 sqrtPrice;
        bytes data;
    }

    /// @notice ArrakisUniV3ERC4626 constructor
    /// @param _gUniPool Compound cToken to wrap
    /// @param _name ERC20 name of the vault shares token
    /// @param _symbol ERC20 symbol of the vault shares token
    constructor(
        address _gUniPool,
        string memory _name,
        string memory _symbol,
        bool isToken0, //if true, token0 in the pool is the asset, else token1 is the asset
        address _arrakisRouter,
        address _gauge,  // the contract which gives staking Rewards
        uint160 _slippage  // 50 would give you 2% slippage which  means sqrtPrice +/- 2 tickSpaces
    )
        ERC4626(
            ERC20(
                isToken0
                    ? address(IGUniPool(_gUniPool).token0())
                    : address(IGUniPool(_gUniPool).token1())
            ),
            _name,
            _symbol
        )
    {
        arrakisVault = IGUniPool(_gUniPool);
        zeroForOne = isToken0;
        arrakisRouter = IArrakisRouter(_arrakisRouter);
        gauge = IGauge(_gauge);
        slippage = _slippage;
        blah = zeroForOne;
        non_asset = zeroForOne? arrakisVault.token1(): arrakisVault.token0();
        // doing it one time instead of each and every deposit/withdrawal swaps
        _approveTokenIfNeeded(address(asset), address(arrakisRouter));
        _approveTokenIfNeeded(address(non_asset), address(arrakisRouter));
        _approveTokenIfNeeded(address(non_asset), address(arrakisVault.pool()));
        // Used in testing
        manager = msg.sender;
    }

    function beforeWithdraw(uint256 underlyingLiquidity, uint256)
        internal
        override
    {
        // getting the pool liquidity from arrakis vault
        IUniswapV3Pool uniPool = arrakisVault.pool();
        (uint128 liquidity_, , , , ) = uniPool.positions(
            arrakisVault.getPositionID()
        );
        uint256 sharesToWithdraw = (underlyingLiquidity *
            arrakisVault.totalSupply()) / liquidity_;
        // withdraw from staking contract 
        gauge.withdraw(sharesToWithdraw);
        // burn arrakis lp
        arrakisVault.burn(sharesToWithdraw, address(this));

        uint256 nonAssetBal = non_asset.balanceOf(address(this));
        // should be moved to new place later!
        (uint160 sqrtPriceX96, , , , , , ) = uniPool.slot0();
        uint160 twoPercentSqrtPrice = sqrtPriceX96 / slippage;
        // calculating slippage for 2% +/- the current tick of the uniPool for swapping
        swapParams memory params = swapParams({
            receiver: address(this),
            direction: !zeroForOne,
            amount: int256(nonAssetBal),
            sqrtPrice: !zeroForOne
                ? sqrtPriceX96 - (twoPercentSqrtPrice)
                : sqrtPriceX96 + (twoPercentSqrtPrice),
            data: ""
        });
        // swap the non_asset total amount to withdrawable asset
        _paramSwap(params);
    }

    /// what is the underlying balance of the liquidity does this contract hold
    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        (uint128 liquidity_, , , , ) = arrakisVault.pool().positions(
            arrakisVault.getPositionID()
        );
        uint256 liquidity = (gauge.balanceOf(address(this)) * liquidity_) /
            arrakisVault.totalSupply();
        return liquidity;
    }

    function afterDeposit(uint256 underlyingAmount, uint256) internal override {
        ERC20 token0 = arrakisVault.token0();
        ERC20 token1 = arrakisVault.token1();
        (uint160 sqrtRatioX96, , , , , , ) = arrakisVault.pool().slot0();
         uint256 priceDecimals = (1 ether *
            ((sqrtRatioX96 * sqrtRatioX96) / X96)) / X96;

        // multiplying the price decimals by 1e12 as the price you get from sqrtRationX96 is 6 decimals but need 18 decimal value for this method
        (bool _direction,uint256 swapAmount) = getRebalanceParams(arrakisVault, zeroForOne ? underlyingAmount: 0, !zeroForOne ? underlyingAmount: 0, 
        priceDecimals * 1e12);
        
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

        //escaping stack too deep error
        _paramSwap(params);

        // we need a final swap to put the remaining amount of tokens into liquidity as before swap might have moved the liquidity positions needed.
        uint256 token0Bal = token0.balanceOf(address(this));
        uint256 token1Bal = token1.balanceOf(address(this));
        (uint256 amount0Used,uint256 amount1Used, ) = arrakisVault.getMintAmounts(
            token0Bal,
            token1Bal
        );
        arrakisRouter
            .addLiquidityAndStake(
                gauge,
                token0Bal,
                token1Bal,
                amount0Used,
                amount1Used,
                address(this)
            );

        // dust measure 
        console.log("Amounts used", amount0Used, amount1Used);
        console.log("balance of non_asset",non_asset.name(), non_asset.balanceOf(address(this)));
        console.log("balance of asset",asset.name(), asset.balanceOf(address(this)));
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }
        uint256 liquidity;
        // Check for rounding error since we round down in previewRedeem.
        require((liquidity = previewRedeem(shares)) != 0, "ZERO_ASSETS");
        beforeWithdraw(liquidity, shares);

        _burn(owner, shares);
        assets = asset.balanceOf(address(this));
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    /// @notice Total amount of the underlying asset that
    /// is "managed" by Vault.
    function totalAssets() public view override returns (uint256) {
        return viewUnderlyingBalanceOf();
    }

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

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external {
        require(msg.sender == address(arrakisVault.pool()), "callback caller");

        if (amount0Delta > 0)
            ERC20(address(arrakisVault.token0())).safeTransfer(
                msg.sender,
                uint256(amount0Delta)
            );
        else if (amount1Delta > 0)
            ERC20(address(arrakisVault.token1())).safeTransfer(
                msg.sender,
                uint256(amount1Delta)
            );
    }

    /**
     * @dev allows calling approve for a token to a specific spender
     * @notice this is an internal function. only used to give approval of
     * @notice the funds in this contract to other contracts
     * @param token the token to give approval for
     * @param spender the spender of the token
     */
    function _approveTokenIfNeeded(address token, address spender) private {
        if (ERC20(token).allowance(address(this), spender) == 0) {
            ERC20(token).safeApprove(spender, type(uint256).max);
        }
    }

    /// -----------------------------------------------------------------------
    /// view methods to calculate price for the swapAmounts
    /// -----------------------------------------------------------------------

    function getRebalanceParams(
        IGUniPool pool,
        uint256 amount0In,
        uint256 amount1In,
        uint256 price18Decimals
    ) public view returns (bool zeroForOn_e, uint256 swapAmount) {
        uint256 amount0Left;
        uint256 amount1Left;
        try pool.getMintAmounts(amount0In, amount1In) returns (
            uint256 amount0,
            uint256 amount1,
            uint256
        ) {
            amount0Left = amount0In - amount0;
            amount1Left = amount1In - amount1;
        } catch {
            amount0Left = amount0In;
            amount1Left = amount1In;
        }

        (uint256 gross0, uint256 gross1) = _getUnderlyingOrLiquidity(pool);

        if (gross1 == 0) {
            return (false, amount1Left);
        }

        if (gross0 == 0) {
            return (true, amount0Left);
        }

        uint256 factor0 =
            10**(18 - ERC20(address(pool.token0())).decimals());
        uint256 factor1 =
            10**(18 - ERC20(address(pool.token1())).decimals());
        uint256 weightX18 =
            FullMath.mulDiv(gross0 * factor0, 1 ether, gross1 * factor1);
        uint256 proportionX18 =
            FullMath.mulDiv(weightX18, price18Decimals, 1 ether);
        uint256 factorX18 =
            FullMath.mulDiv(proportionX18, 1 ether, proportionX18 + 1 ether);

        if (amount0Left > amount1Left) {
            zeroForOn_e = true;
            swapAmount = FullMath.mulDiv(
                amount0Left,
                1 ether - factorX18,
                1 ether
            );
        } else if (amount1Left > amount0Left) {
            swapAmount = FullMath.mulDiv(amount1Left, factorX18, 1 ether);
        }
    }

    function _getUnderlyingOrLiquidity(IGUniPool pool)
        internal
        view
        returns (uint256 gross0, uint256 gross1)
    {
        (gross0, gross1) = pool.getUnderlyingBalances();
        if (gross0 == 0 && gross1 == 0) {
            IUniswapV3Pool uniPool = pool.pool();
            (uint160 sqrtPriceX96, , , , , , ) = uniPool.slot0();
            uint160 lowerSqrtPrice = pool.lowerTick().getSqrtRatioAtTick();
            uint160 upperSqrtPrice = pool.upperTick().getSqrtRatioAtTick();
            (gross0, gross1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                lowerSqrtPrice,
                upperSqrtPrice,
                1 ether
            );
        }
    }

    /// -----------------------------------------------------------------------
    /// using this just for simulating swaps for testing whether it accrues yield or not --- Everything below is used in testing. see tests for how we used below methods.
    /// -----------------------------------------------------------------------
    function swap() external {
        uint256 amount;
        amount = ERC20(!blah ? address(arrakisVault.token1()) : address(arrakisVault.token0())).balanceOf(address(this));

        IUniswapV3Pool uniPool = arrakisVault.pool();
        (uint160 sqrtPriceX96, , , , , , ) = uniPool.slot0();
        uint160 twoPercentSqrtPrice = sqrtPriceX96 / 100;
        (int256 amount0Delta, int256 amount1Delta) = uniPool.swap(
            address(this),
            blah,
            int256(amount),
            blah
                ? sqrtPriceX96 - (twoPercentSqrtPrice)
                : sqrtPriceX96 + (twoPercentSqrtPrice),
            ""
        );
        blah = !blah;
    }

    function computeFeesAccrued() external view {
        (, int24 tick, , , , , ) = arrakisVault
            .pool()
            .slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = arrakisVault.pool().positions(arrakisVault.getPositionID());

        // compute current fees earned
        uint256 fee0 = _computeFeesEarned(
            true,
            feeGrowthInside0Last,
            tick,
            liquidity
        ) + uint256(tokensOwed0);
        uint256 fee1 = _computeFeesEarned(
            false,
            feeGrowthInside1Last,
            tick,
            liquidity
        ) + uint256(tokensOwed1);
        console.log("computed fees", fee0, fee1);
    }

    function _computeFeesEarned(
        bool isZero,
        uint256 feeGrowthInsideLast,
        int24 tick,
        uint128 liquidity
    ) private view returns (uint256 fee) {
        uint256 feeGrowthOutsideLower;
        uint256 feeGrowthOutsideUpper;
        uint256 feeGrowthGlobal;
        IUniswapV3Pool pool = arrakisVault.pool();
        if (isZero) {
            feeGrowthGlobal = pool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = pool.ticks(
                arrakisVault.lowerTick()
            );
            (, , feeGrowthOutsideUpper, , , , , ) = pool.ticks(
                arrakisVault.upperTick()
            );
        } else {
            feeGrowthGlobal = pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = pool.ticks(
                arrakisVault.lowerTick()
            );
            (, , , feeGrowthOutsideUpper, , , , ) = pool.ticks(
                arrakisVault.upperTick()
            );
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (tick >= arrakisVault.lowerTick()) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (tick < arrakisVault.upperTick()) {
                feeGrowthAbove = feeGrowthOutsideUpper;
            } else {
                feeGrowthAbove = feeGrowthGlobal - feeGrowthOutsideUpper;
            }

            uint256 feeGrowthInside = feeGrowthGlobal -
                feeGrowthBelow -
                feeGrowthAbove;
            fee =
                (liquidity * (feeGrowthInside - feeGrowthInsideLast)) /
                0x100000000000000000000000000000000;
        }
    }

    function _paramSwap(swapParams memory params) internal {
        IUniswapV3Pool uniPool = arrakisVault.pool();
        (int256 amount0Delta, int256 amount1Delta) = uniPool.swap(
            params.receiver,
            params.direction,
            params.amount,
            params.sqrtPrice,
            params.data
        );
        console.logInt(amount0Delta);
        console.logInt(amount1Delta);
    }

    function getUnderlyingBalances()
        external
        view
        returns (uint256 amount0Current, uint256 amount1Current)
    {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = arrakisVault.pool().slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = arrakisVault.pool().positions(arrakisVault.getPositionID());

        uint256 liquidityBps = viewUnderlyingBalanceOf() * 10_000/liquidity;

        // compute current holdings from liquidity
        (amount0Current, amount1Current) = LiquidityAmounts
            .getAmountsForLiquidity(
            sqrtRatioX96,
            arrakisVault.lowerTick().getSqrtRatioAtTick(),
            arrakisVault.upperTick().getSqrtRatioAtTick(),
            liquidity
        );

        uint256 fee0 =
            _computeFeesEarned(true, feeGrowthInside0Last, tick, liquidity) +
                uint256(tokensOwed0);
        uint256 fee1 =
            _computeFeesEarned(false, feeGrowthInside1Last, tick, liquidity) +
                uint256(tokensOwed1);

        // add any leftover in contract to current holdings
        amount0Current = (amount0Current + fee0) * liquidityBps/10_000 + arrakisVault.token0().balanceOf(address(this));
        amount1Current = (amount1Current + fee1 * liquidityBps/10_000) + arrakisVault.token1().balanceOf(address(this));
    }

    function emergencyWithdrawAssets() external {
        require(msg.sender == manager, "Please be an Owner!");
        asset.safeTransfer(msg.sender, asset.balanceOf(address(this)));
    }
}
