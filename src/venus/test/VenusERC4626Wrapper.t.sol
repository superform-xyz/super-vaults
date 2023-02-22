// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {VenusERC4626Reinvest} from "../VenusERC4626Reinvest.sol";

import {ICERC20} from "../compound/ICERC20.sol";
import {LibCompound} from "../compound/LibCompound.sol";
import {IComptroller} from "../compound/IComptroller.sol";

contract VenusERC4626WrapperTest is Test {
    uint256 public fork;

    string BSC_RPC_URL = vm.envString("BSC_RPC_URL");

    address public manager;
    address public alice;
    address public bob;

    /// Venus protocol constants
    address VENUS_COMPTROLLER = vm.envAddress("VENUS_COMPTROLLER");
    address VENUS_REWARD_XVS = vm.envAddress("VENUS_REWARD_XVS");

    /// Test USDC Vault
    address VENUS_USDC_ASSET = vm.envAddress("VENUS_USDC_ASSET");
    address VENUS_VUSDC_CTOKEN = vm.envAddress("VENUS_VUSDC_CTOKEN");
    address VENUS_SWAPTOKEN_USDC = vm.envAddress("VENUS_SWAPTOKEN_USDC");
    address VENUS_PAIR1_USDC = vm.envAddress("VENUS_PAIR1_USDC");
    address VENUS_PAIR2_USDC = vm.envAddress("VENUS_PAIR2_USDC");

    VenusERC4626Reinvest public vault;
    ERC20 public asset;
    ERC20 public reward;
    ICERC20 public cToken;
    IComptroller public comptroller;

    constructor() {
        fork = vm.createFork(BSC_RPC_URL);
        
        /// 21_375_198
        vm.rollFork(fork, 21_375_198);
        vm.selectFork(fork);

        manager = msg.sender;
        comptroller = IComptroller(VENUS_COMPTROLLER);

        setVault(
            ERC20(vm.envAddress("VENUS_USDC_ASSET")),
            ERC20(vm.envAddress("VENUS_REWARD_XVS")),
            ICERC20(vm.envAddress("VENUS_VUSDC_CTOKEN")),
            comptroller
        );

        asset = ERC20(VENUS_USDC_ASSET);
        reward = ERC20(VENUS_REWARD_XVS);
        cToken = ICERC20(VENUS_VUSDC_CTOKEN);
    }

    function setVault(
        ERC20 underylyingAsset,
        ERC20 reward_,
        ICERC20 cToken_,
        IComptroller comptroller_
    ) public {
        vm.startPrank(manager);

        asset = underylyingAsset;
        reward = reward;
        cToken = cToken_;

        vault = new VenusERC4626Reinvest(
            underylyingAsset,
            reward_,
            cToken_,
            comptroller_,
            manager
        );

        vm.stopPrank();
    }

    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 100000 ether);
        deal(address(asset), bob, 100000 ether);
    }

    function testDepositWithdrawUSDC() public {
        uint256 amount = 10 ether;

        vm.startPrank(alice);

        uint256 aliceUnderlyingAmount = amount;
        uint256 aliceBalanceBeforeDeposit = asset.balanceOf(alice);

        asset.approve(address(vault), aliceUnderlyingAmount);

        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        console.log("aliceShareAmount", aliceShareAmount);

        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);

        console.log("aliceAssetsToWithdraw", aliceAssetsToWithdraw);

        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        uint256 aliceBalanceBeforeWithdraw = asset.balanceOf(alice);
        uint256 expectedAssetsAfterWithdraw = aliceBalanceBeforeWithdraw +
            aliceAssetsToWithdraw;
        console.log("aliceBalanceBeforeWithdraw", aliceBalanceBeforeWithdraw);

        uint256 aliceSharesBurned = vault.withdraw(
            aliceAssetsToWithdraw,
            alice,
            alice
        );
        uint256 aliceBalanceAfterWithdraw = asset.balanceOf(alice);

        console.log("aliceBalanceBeforeDeposit", aliceBalanceBeforeDeposit);
        console.log("aliceBalanceAfterWithdraw", aliceBalanceAfterWithdraw);

        assertEq(aliceSharesBurned, aliceShareAmount);
        assertEq(expectedAssetsAfterWithdraw, aliceBalanceAfterWithdraw);
    }

    function testDepositWithdrawBUSD() public {
        setVault(
            ERC20(vm.envAddress("VENUS_BUSD_ASSET")),
            ERC20(vm.envAddress("VENUS_REWARD_XVS")),
            ICERC20(vm.envAddress("VENUS_BUSD_CTOKEN")),
            comptroller
        );

        uint256 amount = 100 ether;

        vm.startPrank(alice);

        uint256 aliceUnderlyingAmount = amount;

        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vault.withdraw(aliceAssetsToWithdraw, alice, alice);
    }

    function testHarvest() public {
        uint256 amount = 10000 ether;

        fork = vm.createFork(BSC_RPC_URL);
        
        setVault(
            ERC20(vm.envAddress("VENUS_USDC_ASSET")),
            ERC20(vm.envAddress("VENUS_REWARD_XVS")),
            ICERC20(vm.envAddress("VENUS_VUSDC_CTOKEN")),
            comptroller
        );

        vm.startPrank(manager);
        vault.setRoute(
            VENUS_SWAPTOKEN_USDC,
            VENUS_PAIR1_USDC,
            VENUS_PAIR2_USDC
        );
        vm.stopPrank();

        vm.startPrank(alice);

        uint256 aliceUnderlyingAmount = amount;

        asset.approve(address(vault), aliceUnderlyingAmount);
        vault.deposit(aliceUnderlyingAmount, alice);

        console.log("totalAssets before harvest", vault.totalAssets());

        deal(address(reward), address(vault), 1 ether);

        assertEq(reward.balanceOf(address(vault)), 1 ether);

        vault.harvest(0);
        assertEq(reward.balanceOf(address(vault)), 0);

        console.log("totalAssets after harvest", vault.totalAssets());
    }
}
