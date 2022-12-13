// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapV2ERC4626Swap} from "../swap-built-in/UniswapV2ERC4626Swap.sol";

/// TODO: Add testing for the other Vault
/// TODO: Factory+init solves it
// import {UniswapV2WrapperERC4626Swap} from "../double-sided/swap-built-in/UniswapV2token1.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";

contract UniswapV2TestSwap is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;
    uint256 public immutable ONE_E18 = 1 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    UniswapV2ERC4626Swap public vault;

    string name = "UniV2ERC4626WrapperSwapper";
    string symbol = "UFC4626";
    ERC20 public dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUniswapV2Pair public pair =
        IUniswapV2Pair(0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5);
    IUniswapV2Router public router =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public alice;
    address public bob;
    address public manager;

    uint256 public slippage = 30; /// 0.3

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new UniswapV2ERC4626Swap(
            dai,
            name,
            symbol,
            router,
            pair,
            slippage
        );
        
        alice = address(0x1);
        bob = address(0x2);
        manager = msg.sender;

        deal(address(dai), alice, ONE_THOUSAND_E18 * 10);
        deal(address(dai), bob, ONE_THOUSAND_E18 * 10);

        deal(address(usdc), alice, 1000e6 * 10);
    }

    function testDepositWithdraw() public {
        
        /// @dev If testing with USDC, use this
        // uint256 amountE6 = 100e6;
        // uint256 amountAdjustedE6 = 95e6;

        /// @dev Default testing with DAI (e18)
        uint256 amount = 100 ether;
        uint256 amountAdjusted = 95 ether;

        vm.startPrank(alice);

        dai.approve(address(vault), amount);

        uint256 aliceShareAmount = vault.deposit(amount, alice);
        uint256 previewWithdraw = vault.previewWithdraw(amountAdjusted);

        console.log("aliceShareAmount", aliceShareAmount);
        console.log(previewWithdraw, " shares to burn for ", amountAdjusted, " assets");

        uint256 sharesBurned = vault.withdraw(amountAdjusted, alice, alice);

        console.log("aliceSharesBurned", sharesBurned);
    }

    function testMultipleDepositWithdraw() public {
        uint256 amount = 100 ether;
        uint256 amountAdjusted = 95 ether;

        /// Step 1: Alice deposits 100 tokens, no withdraw
        vm.startPrank(alice);
        dai.approve(address(vault), amount);
        uint256 aliceShareAmount = vault.deposit(amount, alice);
        console.log("aliceShareAmount", aliceShareAmount);
        vm.stopPrank();

        /// Step 2: Bob deposits 100 tokens, no withdraw
        vm.startPrank(bob);
        dai.approve(address(vault), amount);
        uint256 bobShareAmount = vault.deposit(amount, bob);
        console.log("bobShareAmount", bobShareAmount); 
        vm.stopPrank();
       
        /// Step 3: Alice withdraws 95 tokens
        vm.startPrank(alice);
        uint256 sharesBurned = vault.withdraw(amountAdjusted, alice, alice);
        console.log("aliceSharesBurned", sharesBurned); 
        vm.stopPrank();

        /// Step 4: Bob withdraws max amount of asset from shares
        vm.startPrank(bob);
        uint256 assetsToWithdraw = vault.previewRedeem(bobShareAmount);
        console.log("assetsToWithdraw", assetsToWithdraw);
        sharesBurned = vault.withdraw(assetsToWithdraw, bob, bob); 
        console.log("bobSharesBurned", sharesBurned); 

    }

    // function testMintRedeem() public {
    //     uint256 amountInit = 1 ether;
    //     uint256 amountOfSharesToMint = 44335667953475;

    //     /// Init vault neccessary to avoid return 0; for every call, forever
    //     /// TODO: Deploymen of UniswapV2WrapperERC4626Swap should happen from factory
    //     vm.startPrank(bob);
    //     dai.approve(address(vault), amountInit);
    //     vault.deposit(amountInit, bob);
    //     vm.stopPrank();
    //     /// BACK TO REGULAR FLOW

    //     vm.startPrank(alice);

    //     uint256 assetsToApprove = vault.previewMint(amountOfSharesToMint);

    //     dai.approve(address(vault), assetsToApprove);

    //     uint256 aliceAssetsMinted = vault.mint(amountOfSharesToMint, alice);
    //     console.log("alice", aliceAssetsMinted);

    //     uint256 aliceBalanceOfShares = vault.balanceOf(alice);
    //     console.log("aliceBalanceOfShares", aliceBalanceOfShares);
    //     uint256 alicePreviewRedeem = vault.previewRedeem(aliceBalanceOfShares);
    //     console.log("alicePreviewRedeem", alicePreviewRedeem);
        
    //     uint256 sharesBurned = vault.redeem(alicePreviewRedeem, alice, alice);
    //     console.log("sharesBurned", sharesBurned);
    // }

}
