// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {AaveV3ERC4626ReinvestUni} from "../AaveV3ERC4626ReinvestUni.sol";
import {AaveV3ERC4626ReinvestUniFactory} from "../AaveV3ERC4626ReinvestUniFactory.sol";

import {IRewardsController} from "../../aave-v3/external/IRewardsController.sol";
import {IPool} from "../external/IPool.sol";

contract AaveV3ERC4626ReinvestUniTest is Test {
    ////////////////////////////////////////

    address public manager;
    address public alice;
    address public bob;

    uint256 public ethFork;
    uint256 public ftmFork;
    uint256 public avaxFork;
    uint256 public polyFork;
    uint256 public optiFork;

    string ETH_RPC_URL = vm.envString("ETHEREUM_RPC_URL");
    string FTM_RPC_URL = vm.envString("FANTOM_RPC_URL");
    string AVAX_RPC_URL = vm.envString("AVALANCHE_RPC_URL");
    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");
    string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");

    AaveV3ERC4626ReinvestUni public vault;
    AaveV3ERC4626ReinvestUniFactory public factory;

    ERC20 public asset;
    ERC20 public aToken;

    IRewardsController public rewards;
    IPool public lendingPool;

    address public swapToken;
    address public pair1;
    address public pair2;

    ////////////////////////////////////////

    constructor() {
        ethFork = vm.createFork(ETH_RPC_URL);
        ftmFork = vm.createFork(FTM_RPC_URL);
        polyFork = vm.createFork(POLYGON_RPC_URL);

        /// @dev OP REWARDS on Optimism
        optiFork = vm.createFork(OPTIMISM_RPC_URL);

        manager = msg.sender;

        vm.selectFork(optiFork);
        vm.rollFork(24518058);
        rewards = IRewardsController(vm.envAddress("AAVEV3_OPTIMISM_REWARDS"));
        lendingPool = IPool(vm.envAddress("AAVEV3_OPTIMISM_LENDINGPOOL"));

        factory = new AaveV3ERC4626ReinvestUniFactory(
            lendingPool,
            rewards,
            manager
        );

        (, AaveV3ERC4626ReinvestUni v_) = setVault(
            ERC20(vm.envAddress("AAVEV3_OPTIMISM_USDC"))
        );

        /// @dev Set rewards & routes (to abstract)
        swapToken = vm.envAddress("AAVE_V3_POLYGON_WMATIC_USDC_POOL");

        vault = v_;
        console.log("Vault deployed at", address(vault));
    }

    function setVault(ERC20 _asset)
        public
        returns (ERC4626 vault_, AaveV3ERC4626ReinvestUni vaultERC4626_)
    {
        vm.startPrank(manager);

        /// @dev If we need strict ERC4626 interface
        vault_ = factory.createERC4626(_asset);

        /// @dev If we need to use the AaveV2ERC4626Reinvest interface with harvest
        vaultERC4626_ = AaveV3ERC4626ReinvestUni(address(vault_));

        asset = vault_.asset();
        vault = vaultERC4626_;

        vm.stopPrank();
    }

    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        /// TODO: Should be e18 by default
        deal(address(asset), alice, 10000e6);
        deal(address(asset), bob, 10000e6);
    }

    function testFailManagerCreateERC4626() public {
        vm.startPrank(alice);
        factory.createERC4626(ERC20(vm.envAddress("AAVEV3_AVAX_DAI")));
    }

    function testFailManagerSetRewards() public {
        vm.startPrank(alice);

        /// @dev Should fail because we setRewards only as Manager contract
        factory.setRewards(vault);

        /// @dev Should fail because we can only set from Factory contract
        vault.setRewards();

        vm.stopPrank();

        vm.startPrank(manager);
        /// @dev Should fail because only Manager contract can be a setter, not manager itself
        vault.setRewards();
    }

    function testFailManagerSetRoutes() public {
        vm.startPrank(alice);
        factory.setRoutes(vault, swapToken, 500, address(0), 0);
        vm.stopPrank();

        vm.startPrank(manager);
        /// @dev Should fail because only Manager contract can be a setter, not manager itself
        vault.setRoutes(swapToken, 500, address(0), 0);
    }

    function testSingleDepositWithdrawUSDC() public {
        uint256 aliceUnderlyingAmount = 100e6;

        vm.prank(alice);
        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        /// @notice Expect exchange rate to be 1:1 on initial deposit.
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

    function testSingleMintRedeemUSDC() public {
        vm.startPrank(alice);

        uint256 amount = 100e6;

        uint256 aliceShareAmount = amount;

        asset.approve(address(vault), aliceShareAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceShareAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        uint256 aliceUnderlyingAmount = vault.mint(aliceShareAmount, alice);

        /// @notice Expect exchange rate to be 1:1 on initial mint.
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

    function testHarvester() public {
        uint256 aliceUnderlyingAmount = 100e6;

        /// Spoof IncentiveV3 contract storage var
        vm.startPrank(manager);
        address[] memory rewardTokens = factory.setRewards(vault);

        console.log("rewardTokens", rewardTokens[0]);
        console.log("routes", swapToken, pair1, pair2);

        if (rewardTokens.length == 1) {
            factory.setRoutes(vault, rewardTokens[0], 3000, address(0), 0);
        } else {
            console.log("more than 1 reward token");
        }

        vm.stopPrank();
        ///////////////////////////

        vm.startPrank(alice);

        asset.approve(address(vault), aliceUnderlyingAmount);
        vm.warp(block.timestamp + 1 days);
        vault.deposit(aliceUnderlyingAmount, alice);

        uint256 beforeHarvest = vault.totalAssets();
        uint256 beforeHarvestReward = ERC20(rewardTokens[0]).balanceOf(
            address(vault)
        );

        console.log("totalAssets before harvest", beforeHarvest);
        console.log("rewardBalance before harvest", beforeHarvestReward);

        uint256[] memory minAmount = new uint256[](1);
        minAmount[0] = 0;
        vm.warp(block.timestamp + 1 days);
        vault.harvest(minAmount);

        uint256 afterHarvest = vault.totalAssets();
        uint256 afterHarvestReward = ERC20(rewardTokens[0]).balanceOf(
            address(vault)
        );
        assertGt(afterHarvest, beforeHarvest);
        console.log("totalAssets after harvest", afterHarvest);
        console.log("rewardBalance after harvest", afterHarvestReward);
    }
}
