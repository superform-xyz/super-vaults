// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {VenusERC4626Reinvest} from "../VenusERC4626Reinvest.sol";

import {ICERC20} from "../compound/ICERC20.sol";
import {LibCompound} from "../compound/LibCompound.sol";
import {IComptroller} from "../compound/IComptroller.sol";

contract VenusERC4626WrapperTest is Test {
    uint256 public fork;

    string BSC_RPC_URL = vm.envString("BSC_MAINNET_RPC");

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

    /// Write to storage for a duration of test TODO: Change. Should be only by invoke + as fallback
    VenusERC4626Reinvest public vault;
    ERC20 public asset;
    ERC20 public reward;
    ICERC20 public cToken;
    IComptroller public comptroller;

    /// @dev constructor runs only once
    constructor() {
        fork = vm.createFork(BSC_RPC_URL);
        vm.selectFork(fork);
        manager = msg.sender;
        comptroller = IComptroller(VENUS_COMPTROLLER);

        /// Set vault as fallback
        /// @dev NOTE: This is neccessary only because we do not have Factory deployment for Venus
        setVault(
            ERC20(vm.envAddress("VENUS_USDC_ASSET")),
            ERC20(vm.envAddress("VENUS_REWARD_XVS")),
            ICERC20(vm.envAddress("VENUS_VUSDC_CTOKEN")),
            comptroller,
            "VENUS_SWAPTOKEN_USDC",
            "VENUS_PAIR1_USDC",
            "VENUS_PAIR2_USDC"
        );

        /// Init USDC vault always as fallback
        /// @dev NOTE: This is neccessary only because we do not have Factory deployment for Venus
        asset = ERC20(VENUS_USDC_ASSET);
        reward = ERC20(VENUS_REWARD_XVS);
        cToken = ICERC20(VENUS_VUSDC_CTOKEN);
    }

    function setVault(
        ERC20 underylyingAsset,
        ERC20 reward_,
        ICERC20 cToken_,
        IComptroller comptroller_,
        string memory swapToken,
        string memory pair1,
        string memory pair2
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
            vm.envAddress(swapToken),
            vm.envAddress(pair1),
            vm.envAddress(pair2),
            manager
        );

        vm.stopPrank();
    }

    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 1000 ether);
        deal(address(asset), bob, 1000 ether);
    }

    function testDepositWithdrawUSDC() public {
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

    function testDepositWithdrawBUSD() public {
        setVault(
            ERC20(vm.envAddress("VENUS_BUSD_ASSET")),
            ERC20(vm.envAddress("VENUS_REWARD_XVS")),
            ICERC20(vm.envAddress("VENUS_BUSD_CTOKEN")),
            comptroller,
            "VENUS_SWAPTOKEN_BUSD",
            "VENUS_PAIR1_BUSD",
            "VENUS_PAIR2_BUSD"
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
        setVault(
            ERC20(vm.envAddress("VENUS_USDC_ASSET")),
            ERC20(vm.envAddress("VENUS_REWARD_XVS")),
            ICERC20(vm.envAddress("VENUS_VUSDC_CTOKEN")),
            comptroller,
            "VENUS_SWAPTOKEN_USDC",
            "VENUS_PAIR1_USDC",
            "VENUS_PAIR2_USDC"
        );

        uint256 amount = 100 ether;

        vm.startPrank(alice);

        uint256 aliceUnderlyingAmount = amount;

        asset.approve(address(vault), aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        console.log("totalAssets before harvest", vault.totalAssets());

        deal(address(reward), address(vault), 1000 ether);
        assertEq(reward.balanceOf(address(vault)), 1000 ether);
        vault.harvest();
        assertEq(reward.balanceOf(address(vault)), 0);

        console.log("totalAssets after harvest", vault.totalAssets());
    }
}
