// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { ERC4626 } from "solmate/mixins/ERC4626.sol";

import { GeistERC4626Reinvest } from "../GeistERC4626Reinvest.sol";

import { IGLendingPool } from "../external/IGLendingPool.sol";
import { IMultiFeeDistribution } from "../external/IMultiFeeDistribution.sol";
import { DexSwap } from "../../_global/swapUtils.sol";

contract GeistERC4626ReinvestTest is Test {
    ////////////////////////////////////////

    address public manager;
    address public alice;
    address public bob;

    uint256 public ethFork;
    uint256 public ftmFork;
    uint256 public avaxFork;
    uint256 public polyFork;

    string ETH_RPC_URL = vm.envString("ETHEREUM_RPC_URL");
    string FTM_RPC_URL = vm.envString("FANTOM_RPC_URL");
    string AVAX_RPC_URL = vm.envString("AVALANCHE_RPC_URL");
    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");

    GeistERC4626Reinvest public vault;

    ERC20 public asset = ERC20(vm.envAddress("GEIST_DAI_ASSET"));
    ERC20 public aToken = ERC20(vm.envAddress("GEIST_DAI_ATOKEN"));
    ERC20 public rewardToken = ERC20(vm.envAddress("GEIST_REWARD_TOKEN"));
    IMultiFeeDistribution public rewards = IMultiFeeDistribution(vm.envAddress("GEIST_REWARDS_DISTRIBUTION"));
    IGLendingPool public lendingPool = IGLendingPool(vm.envAddress("GEIST_LENDINGPOOL"));

    ////////////////////////////////////////

    function setUp() public {
        /// 	48129547
        ftmFork = vm.createFork(FTM_RPC_URL, 48_129_547);

        manager = msg.sender;

        vm.selectFork(ftmFork);

        vault = new GeistERC4626Reinvest(
            asset,
            aToken,
            rewards,
            lendingPool,
            rewardToken,
            manager
        );

        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 10_000 ether);
        deal(address(asset), bob, 10_000 ether);
    }

    function testSingleDepositWithdraw() public {
        vm.startPrank(alice);

        uint256 amount = 100 ether;

        uint256 aliceUnderlyingAmount = amount;

        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
        assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceUnderlyingAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceUnderlyingAmount);
        assertEq(asset.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

        vault.withdraw(aliceUnderlyingAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    function testSingleMintRedeem() public {
        vm.startPrank(alice);

        uint256 amount = 100 ether;

        uint256 aliceShareAmount = amount;

        asset.approve(address(vault), aliceShareAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceShareAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        uint256 aliceUnderlyingAmount = vault.mint(aliceShareAmount, alice);

        // Expect exchange rate to be 1:1 on initial mint.
        assertEq(aliceShareAmount, aliceUnderlyingAmount);
        assertEq(vault.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
        assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceUnderlyingAmount);
        assertEq(vault.balanceOf(alice), aliceUnderlyingAmount);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceUnderlyingAmount);
        assertEq(asset.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

        vault.redeem(aliceShareAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(asset.balanceOf(alice), alicePreDepositBal);
    }

    /// @notice Tests irrelevant for Base Implementation of Reinvest. Just mocking rewards accrued through transfer.
    function testHarvesterDAI() public {
        vm.startPrank(manager);

        address swapToken = vm.envAddress("GEIST_SWAPTOKEN_DAI");
        address pair1 = vm.envAddress("GEIST_PAIR1_DAI");
        address pair2 = vm.envAddress("GEIST_PAIR2_DAI");

        vault.setRoute(swapToken, pair1, pair2);

        vm.stopPrank();

        vm.startPrank(alice);

        uint256 amount = 100 ether;
        asset.approve(address(vault), amount);
        uint256 aliceShareAmount = vault.deposit(amount, alice);

        vm.roll(block.number + 1_000_000);
        /// @dev Deal 10000 GEIST reward tokens to the vault
        deal(address(rewardToken), address(vault), 10_000 ether);

        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), 100 ether);
        console.log("totalAssets before harvest", vault.totalAssets());
        assertEq(ERC20(rewardToken).balanceOf(address(vault)), 10_000 ether);

        vm.roll(block.number + 6_492_849);
        IMultiFeeDistribution.RewardData[] memory rewardData = vault.getRewardsAccrued();

        for (uint256 i = 0; i < rewardData.length; i++) {
            address tok = rewardData[i].token;
            uint256 amt = rewardData[i].amount;
            console.log("tok", tok, "amt", amt);
        }

        vault.harvest(0);

        assertEq(ERC20(rewardToken).balanceOf(address(vault)), 0);
        console.log("totalAssets after harvest", vault.totalAssets());
    }
}
