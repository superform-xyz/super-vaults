// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapV2WrapperERC4626} from "../double-sided/UniswapV2.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../double-sided/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../double-sided/interfaces/IUniswapV2Router.sol";

contract UniswapV2Test is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;
    uint256 public immutable ONE_E18 = 1 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    UniswapV2WrapperERC4626 public vault;

    string name = "UniV2ERC4626ishWrapper";
    string symbol = "UFC4626";
    ERC20 public dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public pairToken = ERC20(0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5);
    IUniswapV2Pair public pair =
        IUniswapV2Pair(0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5);
    IUniswapV2Router public router =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public alice;
    address public manager;

    uint256 public slippage = 30; /// 0.3

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new UniswapV2WrapperERC4626(
            name,
            symbol,
            pairToken,
            dai,
            usdc,
            router,
            pair,
            slippage
        );
        alice = address(0x1);
        manager = msg.sender;

        deal(address(dai), alice, ONE_THOUSAND_E18 * 2);
        deal(address(usdc), alice, 1000e6 * 2);
        // 887227704489874
    }

    function testSlippage() public {
        uint256 amount = 1 ether;
        uint256 slipMaxAmount = vault.getSlippage(amount);
        uint256 allowedSlip = amount - slipMaxAmount;
        console.log("allowedSlip", allowedSlip);
    }

    function testDepositMath() public {
        uint256 uniLpRequest = 887226683879712;
        // 887226683865896

        vm.startPrank(alice);

        (uint256 assets0, uint256 assets1) = vault.getAssetsAmounts(
            uniLpRequest
        );

        /// this returns min amount of LP, therefore can differ from uniLpRequest
        uint256 poolAmount = vault.getLiquidityAmountOutFor(assets0, assets1);

        console.log("assets0", assets0, "assets1", assets1);
        console.log("liq0", poolAmount);
    }

    /// DepositWithdraw flow where user is using LP amount to calculate assets0/assets1
    function testDepositWithdraw0() public {
        uint256 uniLpRequest = 887226683879712;

        vm.startPrank(alice);

        (uint256 assets0, uint256 assets1) = vault.getAssetsAmounts(
            uniLpRequest
        );

        /// poolAmount != uniLpRequest because this function returns min() amount from reserves
        uint256 poolAmount = vault.getLiquidityAmountOutFor(assets0, assets1);

        dai.approve(address(vault), assets0);
        usdc.approve(address(vault), assets1);

        uint256 expectedSharesFromUniLP = vault.convertToShares(poolAmount);
        uint256 aliceShareAmount = vault.deposit(poolAmount, alice);

        assertEq(expectedSharesFromUniLP, aliceShareAmount);

        uint256 expectedUniLpFromVaultLP = vault.convertToAssets(
            aliceShareAmount
        );

        vault.withdraw(expectedUniLpFromVaultLP, alice, alice);
    }

    /// DepositWithdraw flow where user is using assets0/assets1 to calculate LP amount
    function testDepositWithdraw1() public {
        vm.startPrank(alice);

        uint256 aliceBalanceBeforeDAI = dai.balanceOf(alice);
        uint256 aliceBalanceBeforeUSDC = usdc.balanceOf(alice);

        /// Calculate amount of UniV2LP to get from tokens sent (DAI/USDC)
        /// NOTE: We should provide helper function to get optimal amounts here
        /// As is, user needs to know "optimal amounts" beforehand
        uint256 poolAmount = vault.getLiquidityAmountOutFor(
            ONE_THOUSAND_E18,
            1000e6
        );

        /// Passing expected poolAmount from tokens user wants to supply
        (uint256 assets0, uint256 assets1) = vault.getAssetsAmounts(poolAmount);
        console.log("assets0", assets0, "assets1", assets1);
        console.log("liq0", poolAmount);

        /// Pre-approving correct amounts to receive poolAmount from addLiquidity
        dai.approve(address(vault), assets0);
        usdc.approve(address(vault), assets1);

        uint256 expectedSharesFromUniLP = vault.convertToShares(poolAmount);
        uint256 aliceShareAmount = vault.deposit(poolAmount, alice);

        assertEq(expectedSharesFromUniLP, aliceShareAmount);
        console.log("aliceShareAmount", aliceShareAmount);

        uint256 expectedUniLpFromVaultLP = vault.convertToAssets(
            aliceShareAmount
        );
        console.log("expectedUniLpFromVaultLP", expectedUniLpFromVaultLP);
        uint256 sharesBurned = vault.withdraw(
            expectedUniLpFromVaultLP,
            alice,
            alice
        );

        uint256 aliceBalanceAfterDAI = dai.balanceOf(alice);
        uint256 aliceBalanceAfterUSDC = usdc.balanceOf(alice);

        console.log("sharesBurned", sharesBurned);
        console.log("aliceBalance", vault.balanceOf(alice));
        console.log(
            "DAI & USDC balanace before",
            aliceBalanceBeforeDAI,
            aliceBalanceBeforeUSDC
        );
        console.log(
            "DAI & USDC balanace after",
            aliceBalanceAfterDAI,
            aliceBalanceAfterUSDC
        );

        /// We burn all shares
        assertEq(sharesBurned, aliceShareAmount);
    }

    function testMintRedeem() public {
        uint256 uniLpRequest = 887226683879712;

        vm.startPrank(alice);

        uint256 aliceBalanceBeforeDAI = dai.balanceOf(alice);
        uint256 aliceBalanceBeforeUSDC = usdc.balanceOf(alice);

        (uint256 assets0, uint256 assets1) = vault.getAssetsAmounts(
            uniLpRequest
        );

        /// poolAmount != uniLpRequest because this function returns min() amount from reserves
        uint256 poolAmount = vault.getLiquidityAmountOutFor(assets0, assets1);

        dai.approve(address(vault), assets0);
        usdc.approve(address(vault), assets1);

        uint256 expectedVaultShares = vault.previewMint(poolAmount);
        uint256 aliceShareAmount = vault.mint(poolAmount, alice);
        console.log("sharesMinted", aliceShareAmount);

        assertEq(expectedVaultShares, aliceShareAmount);

        /// Custom impl makes assets returned from redeem not eq to assets transfered but to uniLp burned
        /// It is a cognitivie change, not breaking out of an interface because AUM is 1:1 with uniLP
        uint256 sharesReedem = vault.redeem(aliceShareAmount, alice, alice);

        uint256 aliceBalanceAfterDAI = dai.balanceOf(alice);
        uint256 aliceBalanceAfterUSDC = usdc.balanceOf(alice);

        console.log("sharesReedem", sharesReedem);
        console.log("aliceBalance", vault.balanceOf(alice));
        console.log(
            "DAI & USDC balanace before",
            aliceBalanceBeforeDAI,
            aliceBalanceBeforeUSDC
        );
        console.log(
            "DAI & USDC balanace after",
            aliceBalanceAfterDAI,
            aliceBalanceAfterUSDC
        );
    }
}
