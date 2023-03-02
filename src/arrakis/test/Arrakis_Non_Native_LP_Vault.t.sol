// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import {Utilities} from "../utils/Utilities.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import {ArrakisNonNativeVault, IArrakisRouter, IUniswapV3Pool, LiquidityAmounts, IGUniPool, TickMath, SafeTransferLib} from "../Arrakis_Non_Native_LP_Vault.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IWETH} from "../utils/IWETH.sol";
import {ArrakisFactory} from "../Arrakis_Factory.sol";

interface UniRouter {
    function factory() external view returns (address);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract Arrakis_LP_Test is Test {
    using TickMath for int24;
    using SafeTransferLib for ERC20;
    uint256 public maticFork;
    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");
    ERC20 public arrakisVault;
    bool blah;
    ArrakisNonNativeVault vault;
    ArrakisNonNativeVault public arrakisNonNativeVault;
    ArrakisNonNativeVault public arrakisToken1AsAssetVault;
    ArrakisFactory public arrakisFactory;
    IWETH public WMATIC = IWETH(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address public USDC = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    /// @notice TraderJoe router
    UniRouter private joeRouter =
        UniRouter(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);

    function setUp() public {
        maticFork = vm.createFork(POLYGON_RPC_URL);

        vm.selectFork(maticFork);

        /* ------------------------------- deployments ------------------------------ */
        arrakisVault = ERC20(0x4520c823E3a84ddFd3F99CDd01b2f8Bf5372A82a);

        arrakisFactory = new ArrakisFactory(
            0xbc91a120cCD8F80b819EAF32F0996daC3Fa76a6C
        );

        (arrakisNonNativeVault, arrakisToken1AsAssetVault) = arrakisFactory
            .createArrakisVaults(
                address(arrakisVault),
                "Arrakis WMATIC/USDC LP Vault",
                "aLP4626",
                0x9941C03D31BC8B3aA26E363f7DD908725e1a21bb,
                50
            );
    }

    function getWMATIC(uint256 amt) internal {
        deal(address(this), amt);
        deal(USDC, address(this), amt);
        WMATIC.deposit{value: amt}();
    }

    function paramswap() external {
        uint256 amount;
        amount =
            ERC20(blah ? address(vault.non_asset()) : address(vault.asset()))
                .balanceOf(address(msg.sender)) /
            2;

        IUniswapV3Pool uniPool = vault.arrakisVault().pool();
        (uint160 sqrtPriceX96, , , , , , ) = uniPool.slot0();
        uint160 twoPercentSqrtPrice = sqrtPriceX96 / 100;
        uniPool.swap(
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
        (, int24 tick, , , , , ) = vault.arrakisVault().pool().slot0();
        (
            uint128 liquidity,
            uint256 feeGrowthInside0Last,
            uint256 feeGrowthInside1Last,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = vault.arrakisVault().pool().positions(
                vault.arrakisVault().getPositionID()
            );

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
        IUniswapV3Pool pool = vault.arrakisVault().pool();
        IGUniPool gUniPool = vault.arrakisVault();
        if (isZero) {
            feeGrowthGlobal = pool.feeGrowthGlobal0X128();
            (, , feeGrowthOutsideLower, , , , , ) = pool.ticks(
                gUniPool.lowerTick()
            );
            (, , feeGrowthOutsideUpper, , , , , ) = pool.ticks(
                gUniPool.upperTick()
            );
        } else {
            feeGrowthGlobal = pool.feeGrowthGlobal1X128();
            (, , , feeGrowthOutsideLower, , , , ) = pool.ticks(
                gUniPool.lowerTick()
            );
            (, , , feeGrowthOutsideUpper, , , , ) = pool.ticks(
                gUniPool.upperTick()
            );
        }

        unchecked {
            // calculate fee growth below
            uint256 feeGrowthBelow;
            if (tick >= vault.arrakisVault().lowerTick()) {
                feeGrowthBelow = feeGrowthOutsideLower;
            } else {
                feeGrowthBelow = feeGrowthGlobal - feeGrowthOutsideLower;
            }

            // calculate fee growth above
            uint256 feeGrowthAbove;
            if (tick < vault.arrakisVault().upperTick()) {
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

    function getUnderlyingBalances()
        external
        view
        returns (uint256 amount0Current, uint256 amount1Current)
    {
        IGUniPool gUniPool = vault.arrakisVault();
        (uint160 sqrtRatioX96, , , , , , ) = gUniPool.pool().slot0();
        (uint128 liquidity, , , , ) = gUniPool.pool().positions(
            gUniPool.getPositionID()
        );

        // compute current holdings from liquidity
        (amount0Current, amount1Current) = LiquidityAmounts
            .getAmountsForLiquidity(
                sqrtRatioX96,
                gUniPool.lowerTick().getSqrtRatioAtTick(),
                gUniPool.upperTick().getSqrtRatioAtTick(),
                liquidity
            );
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external {
        IGUniPool gUniPool = vault.arrakisVault();
        require(msg.sender == address(gUniPool.pool()), "callback caller");

        if (amount0Delta > 0)
            ERC20(address(gUniPool.token0())).safeTransfer(
                msg.sender,
                uint256(amount0Delta)
            );
        else if (amount1Delta > 0)
            ERC20(address(gUniPool.token1())).safeTransfer(
                msg.sender,
                uint256(amount1Delta)
            );
    }

    function swap(uint256 amtIn, address[] memory path)
        internal
        returns (uint256)
    {
        ERC20(path[0]).approve(address(joeRouter), amtIn);
        uint256[] memory amts = joeRouter.swapExactTokensForTokens(
            amtIn,
            0,
            path,
            address(this),
            block.timestamp + 1
        );
        return amts[amts.length - 1];
    }

    function testDepositWithToken0AsAssetSuccess() public {
        vault = arrakisNonNativeVault;
        blah = true;
        uint256 amt = 300000e18;
        getWMATIC(amt);
        amt = 2000e18;

        ERC20(address(WMATIC)).approve(address(arrakisNonNativeVault), amt);
        this.computeFeesAccrued();
        emit log_named_uint("deposited amount:", 2000e18);

        uint256 sharesReceived = arrakisNonNativeVault.deposit(
            amt,
            address(this)
        );
        console.log("Underlying balance :", vault.totalAssets());
        /// @dev we simulate the swaps on the same pool we are adding liquidity to, so we can get the fees accrued and test the reinvest.
        console.log("Starting swap simulation on uniswap....");
        uint256 countLoop = 2;
        ERC20(address(WMATIC)).transfer(address(this), 298000e18);
        while (countLoop > 0) {
            this.paramswap();
            countLoop--;
        }
        console.log("swap simulation on uniswap stopped!");

        this.computeFeesAccrued();
        uint256 returnAssets = arrakisNonNativeVault.redeem(
            sharesReceived,
            address(this),
            address(this)
        );
        console.log("Underlying balance :", vault.totalAssets());
        emit log_named_decimal_uint(
            "amount gained through out the duration in the form of deposited Asset",
            returnAssets,
            18
        );
    }

    function testMintWithToken0AsAssetSuccess() public {
        vault = arrakisNonNativeVault;
        blah = true;
        uint256 amt = 300000e18;
        getWMATIC(amt);
        amt = 2000e18;

        ERC20(address(WMATIC)).approve(
            address(arrakisNonNativeVault),
            type(uint256).max
        );
        this.computeFeesAccrued();
        emit log_named_uint("deposited amount:", 2000e18);

        uint256 sharesReceived = arrakisNonNativeVault.mint(amt, address(this));
        console.log("Shares Received :", sharesReceived);
        console.log("Underlying balance :", vault.totalAssets());
        console.log("Starting swap simulation on uniswap....");
        uint256 countLoop = 2;
        ERC20(address(WMATIC)).transfer(address(this), 298000e18);
        while (countLoop > 0) {
            this.paramswap();
            countLoop--;
        }
        console.log("swap simulation on uniswap stopped!");

        this.computeFeesAccrued();
        uint256 returnAssets = arrakisNonNativeVault.withdraw(
            vault.totalAssets() - 1e19,
            address(this),
            address(this)
        );
        console.log("Underlying balance :", vault.totalAssets());
        emit log_named_decimal_uint(
            "amount gained through out the duration in the form of deposited Asset",
            returnAssets,
            18
        );
    }

    function testDepositWithToken1AsAssetSuccess() public {
        vault = arrakisToken1AsAssetVault;
        blah = false;
        uint256 amt = 300000e18;
        // get 2000 WMATIC to user
        getWMATIC(amt);
        // swap for WBTC
        address[] memory path = new address[](2);
        path[0] = address(WMATIC);
        path[1] = USDC;
        uint256 amountUSDC = swap(amt, path);
        ERC20(address(USDC)).approve(
            address(arrakisToken1AsAssetVault),
            amountUSDC
        );
        this.computeFeesAccrued();
        emit log_named_uint("deposited amount:", 2000 * (10**6));

        uint256 sharesReceived = arrakisToken1AsAssetVault.deposit(
            2000 * (10**6),
            address(this)
        );
        console.log("Underlying balance :", vault.totalAssets());
        console.log("Shares received:", sharesReceived);
        console.log("Starting swap simulation on uniswap....");
        uint256 countLoop = 2;
        ERC20(address(USDC)).transfer(
            address(this),
            ERC20(address(USDC)).balanceOf(address(this))
        );
        while (countLoop > 0) {
            this.paramswap();
            countLoop--;
        }
        console.log("swap simulation on uniswap stopped!");
        this.computeFeesAccrued();

        uint256 returnAssets = arrakisToken1AsAssetVault.redeem(
            sharesReceived,
            address(this),
            address(this)
        );
        console.log("Underlying balance :", vault.totalAssets());
        emit log_named_decimal_uint(
            "amount gained through out the duration in the form of deposited Asset",
            returnAssets,
            6
        );
    }

    receive() external payable {}
}
