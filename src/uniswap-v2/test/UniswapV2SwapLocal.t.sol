// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {UniswapV2ERC4626Swap} from "../swap-built-in/UniswapV2ERC4626Swap.sol";
import {UniswapV2ERC4626PoolFactory} from "../swap-built-in/UniswapV2ERC4626PoolFactory.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";

/// @dev Deploying localhost UniswapV2 contracts
import {IUniswapV2Factory} from "../interfaces/IUniswapV2Factory.sol";

import {IUniswapV3Factory} from "../interfaces/IUniswapV3.sol";
import {IUniswapV3Pool} from "../interfaces/IUniswapV3.sol";

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

    uint24 public fee = 3000; /// 0.3

    function setUp() public {
        weth = new WETH();
        token0 = new MockERC20("Test0", "TST0", 18);
        token1 = new MockERC20("Test1", "TST1", 18);

        asset = token0;

        address uniFactory_ = deployCode(
            "src/uniswap-v2/build/UniswapV2Factory.json",
            abi.encode(manager)
        );
        uniFactory = IUniswapV2Factory(uniFactory_);

        address uniRouter_ = deployCode(
            "src/uniswap-v2/build/UniswapV2Router02.json",
            abi.encode(uniFactory_, address(weth))
        );
        uniRouter = IUniswapV2Router(uniRouter_);

        address oracleFactory_ = deployCode(
            "src/uniswap-v2/build/UniswapV3Factory.json"
        );
        oracleFactory = IUniswapV3Factory(oracleFactory_);

        /// @dev NOTE: Raise an issue with foundry, that may be library linking problem in UniV3Pair constructor
        /// @dev Mocked only know (may remove oracle anyways)
        // address oracle_ = deployCode("src/uniswap-v2/build/UniswapV3Pool.json");
        oracle = IUniswapV3Pool(address(0x1337));

        pair = IUniswapV2Pair(
            uniFactory.createPair(address(token0), address(token1))
        );

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

        // seedLiquidity();
    }

    function testGetAddresses() public {
        console.log("UniswapV2FactoryAddress", address(uniFactory));
        console.log("UniswapV2Router02Address", address(uniRouter));
    }

    function testSeedLiquidity() public {
        for (uint256 i = 0; i < 100; i++) {
            uint256 amount = 10000e18;

            /// @dev generate pseudo random address for 100 deposits into pool
            address poolUser = address(
                uint160(
                    uint256(
                        keccak256(abi.encodePacked(i, blockhash(block.number)))
                    )
                )
            );
            vm.startPrank(poolUser);

            /// mint token0 and token1
            token0.mint(poolUser, amount);
            token1.mint(poolUser, amount);

            /// Each deposit will differ a little bit (TODO: better random)
            uint256 randPctg = i + (1 % 900);
            uint256 randAmount = (amount * randPctg) / 1000;
            console.log("poolUser", poolUser, "randAmount", randAmount);

            /// Big initial liquidity
            if (i == 0) {
                randAmount = amount;
            }

            /// add liquidity to pair
            token0.approve(address(uniRouter), randAmount);
            token1.approve(address(uniRouter), randAmount);
            uniRouter.addLiquidity(
                address(token0),
                address(token1),
                randAmount,
                randAmount,
                1,
                1,
                poolUser,
                block.timestamp
            );
            vm.stopPrank();
        }
    }

    // function testFactoryDeploy() public {
    //     vm.startPrank(manager);

    //     (
    //         UniswapV2ERC4626Swap v0,
    //         UniswapV2ERC4626Swap v1,
    //         address oracle_
    //     ) = factory.create(pair, fee);

    //     console.log("v0 name", v0.name(), "v0 symbol", v0.symbol());
    //     console.log("v1 name", v1.name(), "v1 symbol", v1.symbol());
    // }

    // function testDepositWithdraw() public {
    //     uint256 amount = 100 ether;
    //     vm.startPrank(alice);

    //     asset.approve(address(vault), amount);

    //     uint256 aliceShareAmount = vault.deposit(amount, alice);
    //     uint256 aliceShareBalance = vault.balanceOf(alice);
    //     uint256 aliceAssetsToWithdraw = vault.previewRedeem(aliceShareAmount);
    //     uint256 previewWithdraw = vault.previewWithdraw(aliceAssetsToWithdraw);

    //     console.log("aliceShareAmount", aliceShareAmount);
    //     console.log("aliceShareBalance", aliceShareBalance);
    //     console.log(
    //         previewWithdraw,
    //         "shares to burn for",
    //         aliceAssetsToWithdraw,
    //         "assets"
    //     );

    //     uint256 sharesBurned = vault.withdraw(
    //         aliceAssetsToWithdraw,
    //         alice,
    //         alice
    //     );

    //     console.log("aliceSharesBurned", sharesBurned);
    //     console.log("aliceShareBalance", vault.balanceOf(alice));

    //     aliceAssetsToWithdraw = vault.previewRedeem(vault.balanceOf(alice));

    //     console.log("assetsLeftover", aliceAssetsToWithdraw);
    // }

    // function testMultipleDepositWithdraw() public {
    //     uint256 amount = 100 ether;
    //     uint256 amountAdjusted = 95 ether;

    //     /// Step 1: Alice deposits 100 tokens, no withdraw
    //     vm.startPrank(alice);
    //     asset.approve(address(vault), amount);
    //     uint256 aliceShareAmount = vault.deposit(amount, alice);
    //     console.log("aliceShareAmount", aliceShareAmount);
    //     vm.stopPrank();

    //     /// Step 2: Bob deposits 100 tokens, no withdraw
    //     vm.startPrank(bob);
    //     asset.approve(address(vault), amount);
    //     uint256 bobShareAmount = vault.deposit(amount, bob);
    //     console.log("bobShareAmount", bobShareAmount);
    //     vm.stopPrank();

    //     /// Step 3: Alice withdraws 95 tokens
    //     vm.startPrank(alice);
    //     uint256 sharesBurned = vault.withdraw(amountAdjusted, alice, alice);
    //     console.log("aliceSharesBurned", sharesBurned);
    //     vm.stopPrank();

    //     /// Step 4: Bob withdraws max amount of asset from shares
    //     vm.startPrank(bob);
    //     uint256 assetsToWithdraw = vault.previewRedeem(bobShareAmount);
    //     console.log("assetsToWithdraw", assetsToWithdraw);
    //     sharesBurned = vault.withdraw(assetsToWithdraw, bob, bob);
    //     console.log("bobSharesBurned", sharesBurned);
    //     vm.stopPrank();

    //     /// Step 5: Alice withdraws max amount of asset from remaining shares
    //     vm.startPrank(alice);
    //     assetsToWithdraw = vault.previewRedeem(vault.balanceOf(alice));
    //     console.log("assetsToWithdraw", assetsToWithdraw);
    //     sharesBurned = vault.withdraw(assetsToWithdraw, alice, alice);
    //     console.log("aliceSharesBurned", sharesBurned);
    // }

    // function testMintRedeem() public {
    //     /// NOTE:   uniShares          44367471942413
    //     /// we "overmint" shares to avoid revert, all is returned to the user
    //     /// previewMint() returns a correct amount of assets required to be approved to receive this
    //     /// as MINIMAL amount of shares. where function differs is that if user was to run calculations
    //     /// himself, directly against UniswapV2 Pair, calculations would output smaller number of assets
    //     /// required for that amountOfSharesToMint, that is because UniV2 Pair doesn't need to swapJoin()
    //     uint256 amountOfSharesToMint = 44323816369031;
    //     console.log("amountOfSharesToMint", amountOfSharesToMint);
    //     vm.startPrank(alice);

    //     /// NOTE: In case of this ERC4626 adapter, its highly advisable to ALWAYS call previewMint() before mint()
    //     uint256 assetsToApprove = vault.previewMint(amountOfSharesToMint);
    //     console.log("aliceAssetsToApprove", assetsToApprove);

    //     asset.approve(address(vault), assetsToApprove);

    //     uint256 aliceAssetsMinted = vault.mint(amountOfSharesToMint, alice);
    //     console.log("aliceAssetsMinted", aliceAssetsMinted);

    //     uint256 aliceBalanceOfShares = vault.balanceOf(alice);
    //     console.log("aliceBalanceOfShares", aliceBalanceOfShares);

    //     /// TODO: Verify calculation, because it demands more shares than the ones minted for same asset
    //     /// @dev not used for redemption
    //     uint256 alicePreviewRedeem = vault.previewWithdraw(aliceAssetsMinted);
    //     console.log("alicePreviewRedeem", alicePreviewRedeem);
    //     //   aliceBalanceOfShares 44367471942413
    //     //   alicePreviewRedeem   44367200251203
    //     // alice has more shares than previewRedeem asks for to get assetsMinted
    //     uint256 sharesBurned = vault.redeem(alicePreviewRedeem, alice, alice);
    //     console.log("sharesBurned", sharesBurned);

    //     aliceBalanceOfShares = vault.balanceOf(alice);
    //     console.log("aliceBalanceOfShares2", aliceBalanceOfShares);
    // }
}
