// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
// import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IRewardsCore} from "../interfaces/IRewardsCore.sol";
import {IGUniPool} from "../interfaces/IGUniPool.sol";
import {console} from "../test/utils/Console.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "./utils/TickMath.sol";
import {LiquidityAmounts} from "./utils/LiquidityAmounts.sol";


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

    struct swapParams {
        address receiver;
        bool direction;
        int256 amount;
        uint160 sqrtPrice;
        bytes data;
    }

    /// @notice CompoundERC4626 constructor
    /// @param _gUniPool Compound cToken to wrap
    /// @param name ERC20 name of the vault shares token
    /// @param symbol ERC20 symbol of the vault shares token
    constructor(
        address _gUniPool,
        string memory name,
        string memory symbol,
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
            name,
            symbol
        )
    {
        arrakisVault = IGUniPool(_gUniPool);
        zeroForOne = isToken0;
        arrakisRouter = IArrakisRouter(_arrakisRouter);
        gauge = IGauge(_gauge);
        slippage = _slippage;
        blah = zeroForOne;
    }

    function beforeWithdraw(uint256 underlyingLiquidity, uint256)
        internal
        override
    {
        IUniswapV3Pool uniPool = arrakisVault.pool();
        (uint128 liquidity_, , , , ) = uniPool.positions(
            arrakisVault.getPositionID()
        );
        uint256 sharesToWithdraw = (underlyingLiquidity *
            arrakisVault.totalSupply()) / liquidity_;
        gauge.withdraw(sharesToWithdraw);
        arrakisVault.burn(sharesToWithdraw, address(this));
        ERC20 non_asset;
        if(address(arrakisVault.token0()) == address(asset)){
            non_asset = arrakisVault.token1();
        }
        else {
            non_asset = arrakisVault.token0();
        }

        uint256 nonAssetBal = non_asset.balanceOf(address(this));
        non_asset.safeApprove(
            address(uniPool),
            nonAssetBal
        );
        // should be moved to new place later!
        (uint160 sqrtPriceX96, , , , , , ) = uniPool.slot0();
        uint160 twoPercentSqrtPrice = sqrtPriceX96 / slippage;
        swapParams memory params = swapParams({
            receiver: address(this),
            direction: !zeroForOne,
            amount: int256(nonAssetBal),
            sqrtPrice: !zeroForOne
                ? sqrtPriceX96 - (twoPercentSqrtPrice)
                : sqrtPriceX96 + (twoPercentSqrtPrice),
            data: ""
        });
        _paramSwap(params);
    }

    function viewUnderlyingBalanceOf() internal view returns (uint256) {
        (uint128 liquidity_, , , , ) = arrakisVault.pool().positions(
            arrakisVault.getPositionID()
        );
        uint256 liquidity = (gauge.balanceOf(address(this)) * liquidity_) /
            arrakisVault.totalSupply();
        return liquidity;
    }

    function afterDeposit(uint256 underlyingAmount, uint256) internal override {
        // should be moved to new place later!
        IUniswapV3Pool uniPool = arrakisVault.pool();
        (uint160 sqrtPriceX96, , , , , , ) = uniPool.slot0();
        uint160 twoPercentSqrtPrice = sqrtPriceX96 / slippage;
        uint160 lowerLimit = sqrtPriceX96 - (twoPercentSqrtPrice);
        uint160 upperLimit = sqrtPriceX96 + (twoPercentSqrtPrice);
        uint256 swapAmount = underlyingAmount / 3; // initial swap to start calculating expected mint amounts according to the sqrtPrice of arrakisVault
        swapParams memory params = swapParams({
            receiver: address(this),
            direction: zeroForOne,
            amount: int256(swapAmount),
            sqrtPrice: zeroForOne ? lowerLimit : upperLimit,
            data: ""
        });
        //escaping stack too deep error
        _paramSwap(params);
        ERC20 non_asset;
        // calculating amount of asset token that needs to be swapped to non-asset lp token with best liquidity fitting in the arrakis LP
        if(address(arrakisVault.token0()) == address(asset)){
            non_asset = arrakisVault.token1();
        }
        else {
            non_asset = arrakisVault.token0();
        }
        uint256 amountAssetToNonAsset = (arrakisVault.token0().balanceOf(address(this)) *
            ((sqrtPriceX96 * sqrtPriceX96) / X96)) / X96;
        uint256 bps = (amountAssetToNonAsset * 1 ether) /
            (arrakisVault.token1().balanceOf(address(this)) + amountAssetToNonAsset);
        (uint256 amount0Used, uint256 amount1Used, ) = arrakisVault
            .getMintAmounts(
                arrakisVault.token0().balanceOf(address(this)),
                arrakisVault.token1().balanceOf(address(this))
            );
        uint256 token0Left = arrakisVault.token0().balanceOf(address(this)) -
            amount0Used;
        uint256 token1Left = arrakisVault.token1().balanceOf(address(this)) -
            amount1Used;
        bool direction;
        if (token0Left > token1Left) {
            direction = true;
            swapAmount = (token0Left * (1 ether - bps)) / 1 ether;
        } else if (token1Left > token0Left) {
            swapAmount = (token1Left * bps) / 1 ether;
        }
        params.direction = direction;
        params.sqrtPrice = direction ? lowerLimit : upperLimit;
        params.amount = int256(swapAmount);
        _paramSwap(params);
        uint256 token0Bal = arrakisVault.token0().balanceOf(address(this));
        uint256 token1Bal = arrakisVault.token1().balanceOf(address(this));
        ERC20(address(arrakisVault.token0())).safeApprove(
            address(arrakisRouter),
            token0Bal
        );
        ERC20(address(arrakisVault.token1())).safeApprove(
            address(arrakisRouter),
            token1Bal
        );
        (amount0Used, amount1Used, ) = arrakisVault.getMintAmounts(
            token0Bal,
            token1Bal
        );
        (uint256 amount0Delta1, uint256 amount1Delta1, ) = arrakisRouter
            .addLiquidityAndStake(
                gauge,
                token0Bal,
                token1Bal,
                amount0Used,
                amount1Used,
                address(this)
            );
        console.log(amount0Delta1, amount1Delta1);
        token0Bal = asset.balanceOf(address(this));
        token1Bal = non_asset.balanceOf(address(this));
        console.log(token0Bal, token1Bal);
        if (token1Bal != 0) {
            params.receiver = msg.sender;
            params.direction = !zeroForOne;
            params.sqrtPrice = !zeroForOne ? lowerLimit : upperLimit;
            params.amount = int256(token1Bal);
            _paramSwap(params);
        }
        asset.safeTransfer(
            msg.sender,
            token0Bal
        );
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
    /// This is capped by the amount of assets the cToken can be
    /// supplied with.
    /// This is 0 if minting is paused on the cToken.
    function maxDeposit(address) public view override returns (uint256) {
        if (arrakisVault.restrictedMintToggle() == 11111) return 0;
        return type(uint256).max;
    }

    /// @notice maximum amount of shares that can be minted.
    /// This is capped by the amount of assets the cToken can be
    /// supplied with.
    /// This is 0 if minting is paused on the cToken.
    function maxMint(address) public view override returns (uint256) {
        if (arrakisVault.restrictedMintToggle() == 11111) return 0;
        return type(uint256).max;
    }

    /// @notice Maximum amount of assets that can be withdrawn.
    /// This is capped by the amount of cash available on the cToken,
    /// if all assets are borrowed, a user can't withdraw from the vault.
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint256 assetsBalance = convertToAssets(balanceOf[owner]);

        // return cash < assetsBalance ? cash : assetsBalance;

        return 0;
    }

    /// @notice Maximum amount of shares that can be redeemed.
    /// This is capped by the amount of cash available on the cToken,
    /// if all assets are borrowed, a user can't redeem from the vault.
    function maxRedeem(address owner) public view override returns (uint256) {
        return 0;
    }

    /**
     * @dev allows calling approve for a token to a specific sepnder
     * @notice this is an internal function. only used to give approval of
     * @notice the funds in this contract to other contracts
     * @param token the token to give approval for
     * @param spender the spender of the token
     */
    function approveTokenIfNeeded(address token, address spender) external {
        if (ERC20(token).allowance(address(this), spender) == 0) {
            ERC20(token).safeApprove(spender, type(uint256).max);
        }
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

    //using this just for simulating swaps for testing whether it accrues yield or not
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
        // console.logInt(amount0Delta);
        // console.logInt(amount1Delta);
        blah = !blah;
    }

    function emergencyWithdrawAssets() external {
        asset.safeTransfer(msg.sender, asset.balanceOf(address(this)));
    }

    function computeFeesAccrued() external view {
        (uint160 sqrtRatioX96, int24 tick, , , , , ) = arrakisVault
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
}
