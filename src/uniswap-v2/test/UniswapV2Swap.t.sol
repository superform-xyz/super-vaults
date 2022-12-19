// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapV2ERC4626Swap} from "../swap-built-in/UniswapV2ERC4626Swap.sol";
import {UniswapV2ERC4626PoolFactory} from "../swap-built-in/UniswapV2ERC4626PoolFactory.sol";
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
    UniswapV2ERC4626PoolFactory public factory;

    string name = "UniV2-ERC4626";
    string symbol = "Uni4626";
    ERC20 public asset = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IUniswapV2Pair public pair =
        IUniswapV2Pair(0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5);
    IUniswapV2Router public router =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    ERC20 public alternativeAsset = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address public alice;
    address public bob;
    address public manager;

    uint256 public slippage = 30; /// 0.3

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        /// @dev Default Vault for tests
        vault = new UniswapV2ERC4626Swap(
            asset,
            name,
            symbol,
            router,
            pair,
            slippage
        );

        /// @dev Create new pair vaults from factory.create(pair);
        factory = new UniswapV2ERC4626PoolFactory(
            router
        );
        
        alice = address(0x1);
        bob = address(0x2);
        manager = msg.sender;

        deal(address(asset), alice, ONE_THOUSAND_E18 * 10);
        deal(address(asset), bob, ONE_THOUSAND_E18 * 10);

        deal(address(alternativeAsset), alice, 1000e6 * 10);
    }

    function testFactoryDeploy() public {
        vm.startPrank(manager);

        (UniswapV2ERC4626Swap v0, UniswapV2ERC4626Swap v1) = factory.create(pair);

        console.log("v0 name", v0.name(), "v0 symbol", v0.symbol());
        console.log("v1 name", v1.name(), "v1 symbol", v1.symbol());
    }

    function testDepositWithdraw() public {
        
        /// @dev If testing with USDC, use this
        // uint256 amountE6 = 100e6;
        // uint256 amountAdjustedE6 = 95e6;

        /// @dev Default testing with DAI (e18)
        uint256 amount = 100 ether;
        uint256 amountAdjusted = 95 ether;

        vm.startPrank(alice);

        asset.approve(address(vault), amount);

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
        asset.approve(address(vault), amount);
        uint256 aliceShareAmount = vault.deposit(amount, alice);
        console.log("aliceShareAmount", aliceShareAmount);
        vm.stopPrank();

        /// Step 2: Bob deposits 100 tokens, no withdraw
        vm.startPrank(bob);
        asset.approve(address(vault), amount);
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
        vm.stopPrank();

        /// Step 5: Alice withdraws max amount of asset from remaining shares
        vm.startPrank(alice);
        assetsToWithdraw = vault.previewRedeem(vault.balanceOf(alice));
        console.log("assetsToWithdraw", assetsToWithdraw);
        sharesBurned = vault.withdraw(assetsToWithdraw, alice, alice);
        console.log("aliceSharesBurned", sharesBurned);
    }

    function testMintRedeem() public {
        uint256 amountOfSharesToMint = 44323816369031;

        vm.startPrank(alice);

        uint256 assetsToApprove = vault.previewMint(amountOfSharesToMint);

        asset.approve(address(vault), assetsToApprove);

        uint256 aliceAssetsMinted = vault.mint(amountOfSharesToMint, alice);
        console.log("aliceAssetsMinted", aliceAssetsMinted);

        uint256 aliceBalanceOfShares = vault.balanceOf(alice);
        console.log("aliceBalanceOfShares", aliceBalanceOfShares);

        /// TODO: Verify calculation, because it demands more shares than the ones minted for same asset
        /// @dev not used for redemption
        uint256 alicePreviewRedeem = vault.previewWithdraw(aliceAssetsMinted);
        console.log("alicePreviewRedeem", alicePreviewRedeem);
        
        uint256 sharesBurned = vault.redeem(vault.balanceOf(alice), alice, alice);
        console.log("sharesBurned", sharesBurned);
    }

}
