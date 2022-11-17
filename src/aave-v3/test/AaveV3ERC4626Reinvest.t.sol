// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {AaveV3ERC4626Reinvest} from "../AaveV3ERC4626Reinvest.sol";
import {AaveV3ERC4626ReinvestFactory} from "../AaveV3ERC4626ReinvestFactory.sol";

import {IRewardsController} from "../../aave-v3/external/IRewardsController.sol";
import {IPool} from "../external/IPool.sol";

contract AaveV3ERC4626ReinvestTest is Test {
    ////////////////////////////////////////

    address public manager;
    address public alice;
    address public bob;

    uint256 public ethFork;
    uint256 public ftmFork;
    uint256 public avaxFork;
    uint256 public polyFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");
    string FTM_RPC_URL = vm.envString("FTM_MAINNET_RPC");
    string AVAX_RPC_URL = vm.envString("AVAX_MAINNET_RPC");
    string POLYGON_MAINNET_RPC = vm.envString("POLYGON_MAINNET_RPC");

    AaveV3ERC4626Reinvest public vault;
    AaveV3ERC4626ReinvestFactory public factory;

    ERC20 public asset;
    ERC20 public aToken;

    IRewardsController public rewards;
    IPool public lendingPool;

    address public rewardToken;

    ////////////////////////////////////////

    constructor() {
        ethFork = vm.createFork(ETH_RPC_URL); /// @dev No rewards on ETH mainnet
        ftmFork = vm.createFork(FTM_RPC_URL); /// @dev No rewards on FTM
        polyFork = vm.createFork(POLYGON_MAINNET_RPC); /// @dev No rewards on Polygon

        /// @dev REWARDS on Avax
        avaxFork = vm.createFork(AVAX_RPC_URL);

        manager = msg.sender;

        vm.selectFork(avaxFork);

        rewards = IRewardsController(vm.envAddress("AAVEV3_AVAX_REWARDS"));
        lendingPool = IPool(vm.envAddress("AAVEV3_AVAX_LENDINGPOOL"));

        /// @dev This makes factory persistent, not always wanted behavior
        factory = new AaveV3ERC4626ReinvestFactory(
            lendingPool,
            rewards,
            manager
        );

        (ERC4626 v, AaveV3ERC4626Reinvest v_) = setVault(
            ERC20(vm.envAddress("AAVEV3_AVAX_USDC"))
        );
        vault = v_;
        console.log("Vault deployed at", address(vault));
    }

    function setVault(ERC20 _asset)
        public
        returns (ERC4626 vault_, AaveV3ERC4626Reinvest _vault_)
    {
        asset = _asset;

        /// @dev If we need strict ERC4626 interface
        vault_ = factory.createERC4626(asset);

        /// @dev If we need to use the AaveV2ERC4626Reinvest interface with harvest
        _vault_ = AaveV3ERC4626Reinvest(address(vault_));

        asset = _vault_.asset();
    }

    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 10000e6);
        deal(address(asset), bob, 10000e6);
    }

    function testFactoryDeploy() public {
        vm.startPrank(manager);

        /// @dev We deploy with different asset than at runtime (constructor)
        ERC4626 vault_ = factory.createERC4626(
            ERC20(vm.envAddress("AAVEV3_AVAX_DAI"))
        );

        /// @dev We don't set global var to a new vault! This vault exists only within function scope
        ERC20 vaultAsset = vault_.asset();

        vm.stopPrank();
        vm.startPrank(alice);

        /// @dev Just check if we can deposit (USDCe6!)
        uint256 amount = 100e6;
        deal(address(vaultAsset), alice, 100e6 ether);
        uint256 aliceUnderlyingAmount = amount;
        vaultAsset.approve(address(vault_), aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault_.deposit(aliceUnderlyingAmount, alice);
    }

    function testSingleDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = 100e6;

        vm.prank(alice);
        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(
            vault.previewWithdraw(aliceShareAmount),
            aliceUnderlyingAmount
        );
        assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceUnderlyingAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceUnderlyingAmount
        );
        assertEq(
            asset.balanceOf(alice),
            alicePreDepositBal - aliceUnderlyingAmount
        );

        vm.prank(alice);
        vault.withdraw(aliceUnderlyingAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    function testSingleMintRedeem() public {
        vm.startPrank(alice);

        uint256 amount = 100e6;

        uint256 aliceShareAmount = amount;

        asset.approve(address(vault), aliceShareAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceShareAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        uint256 aliceUnderlyingAmount = vault.mint(aliceShareAmount, alice);

        // Expect exchange rate to be 1:1 on initial mint.
        assertEq(aliceShareAmount, aliceUnderlyingAmount);
        assertEq(
            vault.previewWithdraw(aliceShareAmount),
            aliceUnderlyingAmount
        );
        assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceUnderlyingAmount);
        assertEq(vault.balanceOf(alice), aliceUnderlyingAmount);
        assertEq(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceUnderlyingAmount
        );
        assertEq(
            asset.balanceOf(alice),
            alicePreDepositBal - aliceUnderlyingAmount
        );

        vault.redeem(aliceShareAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    // function testHarvester() public {
    //     uint256 aliceUnderlyingAmount = 100e6;

    //     vm.startPrank(manager);
    //     /// Move to constructor, set routes

    //     /// Spoof IncentiveV3 contract storage var
    //     address[] memory rewardTokens = vault.setRewards();
    //     console.log("rewardTokens", rewardTokens[0]);
    //     if (rewardTokens.length == 1) {
    //         rewardToken = rewardTokens[0];
    //         deal(address(asset), address(vault), 100 ether);
    //     } else {
    //         console.log("more than 1 reward token");
    //     }
    //     vm.stopPrank();

    //     vm.startPrank(alice);
    //     asset.approve(address(vault), aliceUnderlyingAmount);
    //     uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

    //     assertEq(vault.totalSupply(), aliceShareAmount);
    //     assertEq(vault.totalAssets(), 100 ether);
    //     console.log("totalAssets before harvest", vault.totalAssets());

    //     assertEq(ERC20(rewardToken).balanceOf(address(vault)), 100 ether);
    //     vault.harvest();

    //     assertEq(ERC20(rewardToken).balanceOf(address(vault)), 0);
    //     console.log("totalAssets after harvest", vault.totalAssets());
    // }
}
