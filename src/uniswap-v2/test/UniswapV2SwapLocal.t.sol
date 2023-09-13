// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { WETH } from "solmate/tokens/WETH.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";

import { UniswapV2ERC4626Swap } from "../swap-built-in/UniswapV2ERC4626Swap.sol";
import { UniswapV2ERC4626PoolFactory } from "../swap-built-in/UniswapV2ERC4626PoolFactory.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { IUniswapV2Pair } from "../interfaces/IUniswapV2Pair.sol";
import { IUniswapV2Router } from "../interfaces/IUniswapV2Router.sol";

/// @dev Deploying localhost UniswapV2 contracts
import { IUniswapV2Factory } from "../interfaces/IUniswapV2Factory.sol";

import { IUniswapV3Factory } from "../interfaces/IUniswapV3.sol";
import { IUniswapV3Pool } from "../interfaces/IUniswapV3.sol";

contract UniswapV2TestSwapLocalHost is Test {
    using FixedPointMathLib for uint256;

    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;
    uint256 public immutable ONE_E18 = 1 ether;

    string name = "UniV2-ERC4626";
    string symbol = "Uni4626";

    MockERC20 public token0;
    MockERC20 public token1;

    UniswapV2ERC4626Swap public vault;
    UniswapV2ERC4626PoolFactory public factory;

    ERC20 public asset;
    WETH public weth;

    IUniswapV2Factory public uniFactory;
    IUniswapV2Router public uniRouter;
    IUniswapV2Pair public pair;

    IUniswapV3Factory public oracleFactory;
    IUniswapV3Pool public oracle;

    address public alice;
    address public bob;
    address public manager;

    function setUp() public {
        weth = new WETH();
        token0 = new MockERC20("Test0", "TST0", 18);
        token1 = new MockERC20("Test1", "TST1", 18);

        asset = token0;

        address uniFactory_ = deployCode("src/uniswap-v2/build/UniswapV2Factory.json", abi.encode(manager));
        uniFactory = IUniswapV2Factory(uniFactory_);

        address uniRouter_ =
            deployCode("src/uniswap-v2/build/UniswapV2Router02.json", abi.encode(uniFactory_, address(weth)));
        uniRouter = IUniswapV2Router(uniRouter_);

        address oracleFactory_ = deployCode("src/uniswap-v2/build/UniswapV3Factory.json");

        oracleFactory = IUniswapV3Factory(oracleFactory_);

        /// @dev NOTE: deployCode() does not work with UniswapV3Pool?
        /// temp oracle is probably to be removed
        address oracle_ = oracleFactory.createPool(address(token0), address(token1), 3000);
        oracle = IUniswapV3Pool(oracle_);

        pair = IUniswapV2Pair(uniFactory.createPair(address(token0), address(token1)));

        /// @dev Default Vault for tests
        vault = new UniswapV2ERC4626Swap(
            asset,
            name,
            symbol,
            uniRouter,
            pair,
            oracle
        );

        /// @dev Create new pair vaults from factory.create(pair);
        factory = new UniswapV2ERC4626PoolFactory(uniRouter, oracleFactory);

        alice = address(0x1);
        bob = address(0x2);
        manager = msg.sender;

        deal(address(asset), alice, ONE_THOUSAND_E18 * 10);
        deal(address(asset), bob, ONE_THOUSAND_E18 * 10);

        seedLiquidity();
    }

    function seedLiquidity() public {
        for (uint256 i = 0; i < 100; i++) {
            uint256 amount = 10_000e18;

            /// @dev generate pseudo random address for 100 deposits into pool
            address poolUser = address(uint160(uint256(keccak256(abi.encodePacked(i, blockhash(block.number))))));
            vm.startPrank(poolUser);

            /// mint token0 and token1
            token0.mint(poolUser, amount);
            token1.mint(poolUser, amount);

            /// Each deposit will differ a little bit (TODO: better random)
            uint256 randPctg = i + (1 % 900);
            uint256 randAmount = (amount * randPctg) / 1000;

            /// Big initial liquidity
            if (i == 0) {
                randAmount = amount;
            }

            /// add liquidity to pair
            token0.approve(address(uniRouter), randAmount);
            token1.approve(address(uniRouter), randAmount);
            uniRouter.addLiquidity(
                address(token0), address(token1), randAmount, randAmount, 1, 1, poolUser, block.timestamp
            );
            vm.stopPrank();
        }
    }

    function makeSomeSwaps() public {
        for (uint256 i = 0; i < 100; i++) {
            uint256 amount = 1000e18;

            /// @dev generate pseudo random address for 100 deposits into pool
            address poolUser = address(uint160(uint256(keccak256(abi.encodePacked(i, blockhash(block.number))))));

            vm.startPrank(poolUser);

            /// mint token0 and token1
            token0.mint(poolUser, amount);
            token1.mint(poolUser, amount);

            /// Each deposit will differ a little bit (TODO: better random)
            uint256 randPctg = i + (1 % 900);
            uint256 randAmount = (amount * randPctg) / 1000;

            /// Big initial liquidity
            if (i == 0) {
                randAmount = amount;
            }

            /// add liquidity to pair
            token0.approve(address(uniRouter), randAmount);
            token1.approve(address(uniRouter), randAmount);

            /// swap tokens
            address[] memory path = new address[](2);
            path[0] = address(token0);
            path[1] = address(token1);

            uniRouter.swapExactTokensForTokens(randAmount, 1, path, poolUser, block.timestamp);

            vm.stopPrank();
        }
    }

    function testDepositWithdrawSimulation() public {
        uint256 amount = 100 ether;
        vm.startPrank(alice);

        /// @dev Get values before deposit
        uint256 startBalance = asset.balanceOf(alice);
        /// for Y assets we get X shares
        uint256 previewDepositInit = vault.previewDeposit(amount);
        /// for X shares we get Y assets
        uint256 previewRedeemInit = vault.previewRedeem(previewDepositInit);

        /// @dev Deposit
        asset.approve(address(vault), amount);

        uint256 aliceShareAmount = vault.deposit(amount, alice);
        uint256 aliceShareBalance = vault.balanceOf(alice);

        /// alice should own eq or more shares than she requested for in previewDeposit()
        assertGe(aliceShareAmount, previewDepositInit);
        /// alice shares from deposit are equal to her balance (true only for first deposit)
        assertEq(aliceShareAmount, aliceShareBalance);
        /// alice should have less of an asset on her balance after deposit, by the amount approved
        assertEq(asset.balanceOf(alice), (startBalance - amount));

        /// @dev Simulate yield on UniswapV2Pair
        vm.stopPrank();
        makeSomeSwaps();
        vm.startPrank(alice);

        uint256 aliceAssetsToWithdraw = vault.previewRedeem(aliceShareAmount);
        uint256 aliceSharesToBurn = vault.previewWithdraw(aliceAssetsToWithdraw);

        console.log("aliceSharesToBurn", aliceSharesToBurn);

        /// alice should be able to withdraw more assets than she deposited
        assertGe(aliceAssetsToWithdraw, previewRedeemInit);

        uint256 sharesBurned = vault.withdraw(aliceAssetsToWithdraw, alice, alice);

        /// alice balance should be bigger than her initial balance (yield accrued)
        assertGe(asset.balanceOf(alice), startBalance);
        /// alice should burn less or eq amount of shares than she requested for in previewWithdraw()
        assertLe(sharesBurned, aliceSharesToBurn);

        console.log("aliceSharesBurned", sharesBurned);
        console.log("aliceShareBalance", vault.balanceOf(alice));

        aliceAssetsToWithdraw = vault.previewRedeem(vault.balanceOf(alice));

        console.log("assetsLeftover", aliceAssetsToWithdraw);

        sharesBurned = vault.withdraw(vault.balanceOf(alice), alice, alice);
    }

    function testMintRedeemSimulation() public {
        /// NOTE:   uniShares          44367471942413
        /// we "overmint" shares to avoid revert, all is returned to the user
        /// previewMint() returns a correct amount of assets required to be approved to receive this
        /// as MINIMAL amount of shares. where function differs is that if user was to run calculations
        /// himself, directly against UniswapV2 Pair, calculations would output smaller number of assets
        /// required for that amountOfSharesToMint, that is because UniV2 Pair doesn't need to swapJoin()
        uint256 amountOfSharesToMint = 44_323_816_369_031;
        console.log("amountOfSharesToMint", amountOfSharesToMint);
        vm.startPrank(alice);

        /// @dev Get values before deposit
        uint256 startBalance = asset.balanceOf(alice);

        /// NOTE: In case of this ERC4626 adapter, its highly advisable to ALWAYS call previewMint() before mint()
        uint256 assetsToApprove = vault.previewMint(amountOfSharesToMint);
        console.log("aliceAssetsToApprove", assetsToApprove);

        asset.approve(address(vault), assetsToApprove);

        uint256 aliceAssetsMinted = vault.mint(amountOfSharesToMint, alice);
        console.log("aliceAssetsMinted", aliceAssetsMinted);

        /// @dev Simulate yield on UniswapV2Pair
        vm.stopPrank();
        makeSomeSwaps();
        vm.startPrank(alice);

        uint256 aliceBalanceOfShares = vault.balanceOf(alice);
        console.log("aliceBalanceOfShares", aliceBalanceOfShares);

        assertGe(aliceAssetsMinted, assetsToApprove);
        assertGe(aliceBalanceOfShares, amountOfSharesToMint);
        assertEq(asset.balanceOf(alice), (startBalance - assetsToApprove));

        uint256 aliceAssetsToWithdraw = vault.previewRedeem(aliceBalanceOfShares);
        console.log("aliceAssetsToWithdraw", aliceAssetsToWithdraw);

        uint256 aliceSharesToBurn = vault.previewWithdraw(aliceAssetsToWithdraw);
        console.log("aliceSharesToBurn", aliceSharesToBurn);

        uint256 assetsReceived = vault.redeem(aliceBalanceOfShares, alice, alice);
        console.log("assetsReceived", assetsReceived);

        assertGe(asset.balanceOf(alice), startBalance);
        assertGe((startBalance + aliceAssetsToWithdraw), startBalance);
    }

    function testDepositRedeemSimulation() public {
        uint256 amount = 100 ether;
        vm.startPrank(alice);

        /// @dev Get values before deposit
        uint256 startBalance = asset.balanceOf(alice);
        /// for Y assets we get X shares
        uint256 previewDepositInit = vault.previewDeposit(amount);
        /// for X shares we get Y assets
        uint256 previewRedeemInit = vault.previewRedeem(previewDepositInit);

        /// @dev Deposit
        asset.approve(address(vault), amount);

        uint256 aliceShareAmount = vault.deposit(amount, alice);
        uint256 aliceShareBalance = vault.balanceOf(alice);

        /// alice should own eq or more shares than she requested for in previewDeposit()
        assertGe(aliceShareAmount, previewDepositInit);
        /// alice shares from deposit are equal to her balance (true only for first deposit)
        assertEq(aliceShareAmount, aliceShareBalance);

        /// @dev Simulate yield on UniswapV2Pair
        vm.stopPrank();
        makeSomeSwaps();
        vm.startPrank(alice);

        uint256 aliceAssetsToWithdraw = vault.previewRedeem(aliceShareBalance);
        uint256 aliceSharesToBurn = vault.previewWithdraw(aliceAssetsToWithdraw);

        console.log("aliceSharesToBurn", aliceSharesToBurn);

        /// alice should be able to withdraw more assets than she deposited
        assertGe(aliceAssetsToWithdraw, previewRedeemInit);

        uint256 assetsReceived = vault.redeem(aliceShareBalance, alice, alice);

        /// alice balance should be bigger than her initial balance (yield accrued)
        assertGe(asset.balanceOf(alice), startBalance);
        /// alice receives eq or more assets than she requested for in previewRedeem()
        assertGe(assetsReceived, aliceAssetsToWithdraw);
        /// alice should burn all shares
        assertLe(vault.balanceOf(alice), 0);

        console.log("assetsReceived", assetsReceived);
        console.log("aliceShareBalance", vault.balanceOf(alice));
    }

    function testProtectedDepositWithdraw() public {
        uint256 amount = 100 ether;
        vm.startPrank(alice);

        /// @dev Get values before deposit
        uint256 startBalance = asset.balanceOf(alice);

        /// @dev for Y assets we get X shares
        uint256 previewDepositInit = vault.previewDeposit(amount);

        console.log("previewDepositInit", previewDepositInit);

        /// @dev calculate min shares out (shares expected to receive - slippage)
        uint256 minSharesOut = (previewDepositInit * 997) / 1000;

        console.log("minSharesOut", minSharesOut);

        /// @dev Deposit
        asset.approve(address(vault), amount);
        uint256 aliceShareAmount = vault.deposit(amount, alice, minSharesOut);

        uint256 aliceShareBalance = vault.balanceOf(alice);

        /// alice should own eq or more shares than she requested for in previewDeposit()
        assertGe(aliceShareAmount, previewDepositInit);
        /// alice shares from deposit are equal to her balance (true only for first deposit)
        assertEq(aliceShareAmount, aliceShareBalance);
        /// alice should have less of an asset on her balance after deposit, by the amount approved
        assertEq(asset.balanceOf(alice), (startBalance - amount));
        /// alice should have at least eq amount of shares to minSharesOut
        assertGe(aliceShareAmount, minSharesOut);

        /// @dev Simulate yield on UniswapV2Pair
        vm.stopPrank();
        makeSomeSwaps();
        vm.startPrank(alice);

        uint256 aliceAssetsToWithdraw = vault.previewRedeem(aliceShareAmount);
        uint256 aliceSharesToBurn = vault.previewWithdraw(aliceAssetsToWithdraw);

        console.log("aliceSharesToBurn", aliceSharesToBurn);

        /// alice should be able to withdraw more assets than she deposited
        assertGe(aliceAssetsToWithdraw, amount);

        /// @dev Here, caller assumes trust in previewRedeem, under normal circumstances it should be queried few times
        /// or calculated fully off-chain
        uint256 minAmountOut = vault.previewRedeem(aliceShareBalance);
        /// TODO: Investiage why here we need to give higher slippage?
        minAmountOut = (minAmountOut * 995) / 1000;
        console.log("minAmountOut", minAmountOut);

        uint256 sharesBurned = vault.withdraw(aliceAssetsToWithdraw, alice, alice, minAmountOut);

        /// alice balance should be bigger than her initial balance (yield accrued)
        assertGe(asset.balanceOf(alice), startBalance);
        /// alice should burn less or eq amount of shares than she requested for in previewWithdraw()
        assertLe(sharesBurned, aliceSharesToBurn);

        console.log("aliceSharesBurned", sharesBurned);
        console.log("aliceShareBalance", vault.balanceOf(alice));

        aliceAssetsToWithdraw = vault.previewRedeem(vault.balanceOf(alice));

        console.log("assetsLeftover", aliceAssetsToWithdraw);

        sharesBurned = vault.withdraw(vault.balanceOf(alice), alice, alice);
    }

    function testProtectedMintRedeem() public {
        uint256 amountOfSharesToMint = 44_323_816_369_031;
        console.log("amountOfSharesToMint", amountOfSharesToMint);
        vm.startPrank(alice);

        /// @dev Get values before deposit
        uint256 startBalance = asset.balanceOf(alice);

        /// NOTE: In case of this ERC4626 adapter, its highly advisable to ALWAYS call previewMint() before mint()
        uint256 assetsToApprove = vault.previewMint(amountOfSharesToMint);
        console.log("aliceAssetsToApprove", assetsToApprove);

        asset.approve(address(vault), assetsToApprove);

        /// @dev Caller assumes trust in previewMint, under normal circumstances it should be queried few times or
        /// calculated fully off-chain
        uint256 minSharesOut = (amountOfSharesToMint * 997) / 1000;
        uint256 aliceAssetsMinted = vault.mint(amountOfSharesToMint, alice, minSharesOut);

        console.log("aliceAssetsMinted", aliceAssetsMinted);

        /// @dev Simulate yield on UniswapV2Pair
        vm.stopPrank();
        makeSomeSwaps();
        vm.startPrank(alice);

        uint256 aliceBalanceOfShares = vault.balanceOf(alice);
        console.log("aliceBalanceOfShares", aliceBalanceOfShares);

        assertGe(aliceAssetsMinted, assetsToApprove);
        assertGe(aliceBalanceOfShares, amountOfSharesToMint);
        assertEq(asset.balanceOf(alice), (startBalance - assetsToApprove));

        uint256 aliceAssetsToWithdraw = vault.previewRedeem(aliceBalanceOfShares);
        console.log("aliceAssetsToWithdraw", aliceAssetsToWithdraw);

        uint256 aliceSharesToBurn = vault.previewWithdraw(aliceAssetsToWithdraw);
        console.log("aliceSharesToBurn", aliceSharesToBurn);

        /// @dev Caller assumes trust in previewMint, under normal circumstances it should be queried few times or
        /// calculated fully off-chain
        uint256 minAmountOut = (aliceAssetsToWithdraw * 30) / 1000;
        uint256 assetsReceived = vault.redeem(aliceBalanceOfShares, alice, alice, minAmountOut);

        console.log("assetsReceived", assetsReceived);

        assertGe(asset.balanceOf(alice), startBalance);
        assertGe((startBalance + aliceAssetsToWithdraw), startBalance);
    }
}
