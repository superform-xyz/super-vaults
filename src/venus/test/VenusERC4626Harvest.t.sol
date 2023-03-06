// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {VenusERC4626Reinvest} from "../VenusERC4626Reinvest.sol";

import {IVERC20} from "../external/IVERC20.sol";
import {LibVCompound} from "../external/LibVCompound.sol";
import {IVComptroller} from "../external/IVComptroller.sol";

contract VenusERC4626HarvestTest is Test {
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
    IVERC20 public cToken;
    IVComptroller public comptroller;

    function setVault(
        ERC20 underylyingAsset,
        ERC20 reward_,
        IVERC20 cToken_,
        IVComptroller comptroller_
    ) public {
        vm.startPrank(manager);

        asset = underylyingAsset;
        reward = reward_;
        cToken = cToken_;

        vault = new VenusERC4626Reinvest(
            underylyingAsset,
            reward_,
            cToken_,
            comptroller_,
            manager
        );

        vm.makePersistent(address(vault));

        vm.stopPrank();
    }

    function setUp() public {
        fork = vm.createFork(BSC_RPC_URL, 25_630_086);

        vm.selectFork(fork);

        manager = msg.sender;
        comptroller = IVComptroller(VENUS_COMPTROLLER);

        setVault(
            ERC20(vm.envAddress("VENUS_USDC_ASSET")),
            ERC20(vm.envAddress("VENUS_REWARD_XVS")),
            IVERC20(vm.envAddress("VENUS_VUSDC_CTOKEN")),
            comptroller
        );

        asset = ERC20(VENUS_USDC_ASSET);
        reward = ERC20(VENUS_REWARD_XVS);
        cToken = IVERC20(VENUS_VUSDC_CTOKEN);

        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 100000 ether);
        deal(address(asset), bob, 100000 ether);

        /// @dev Making contracts persistent
        vm.makePersistent(address(comptroller));
        vm.makePersistent(address(asset));
        vm.makePersistent(address(reward));
        vm.makePersistent(address(cToken));
        vm.makePersistent(alice);
        vm.makePersistent(bob);
    }

    function testHarvestUSDC() public {
        uint256 amount = 100000 ether;

        /// @dev split for more deposits to calculate delta correctly
        uint256 halfAmount = amount / 2;

        setVault(
            ERC20(vm.envAddress("VENUS_USDC_ASSET")),
            ERC20(vm.envAddress("VENUS_REWARD_XVS")),
            IVERC20(vm.envAddress("VENUS_VUSDC_CTOKEN")),
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

        asset.approve(address(vault), amount);
        vault.deposit(halfAmount, alice);
        vault.deposit(halfAmount, alice);

        vm.stopPrank();

        vm.rollFork(25_630_500);

        vm.startPrank(bob);
        asset.approve(address(vault), amount);
        vault.deposit(halfAmount, bob);
        vault.deposit(halfAmount, bob);

        vm.stopPrank();

        console.log("--------FIRST ROLL FORK--------");

        vm.rollFork(25_631_000);

        vm.startPrank(alice);
        uint256 totalAssets = vault.totalAssets();
        console.log("block number", block.number);
        console.log("totalAssets first roll", totalAssets);

        uint256 rewardsSeparate = comptroller.venusAccrued(address(vault));
        console.log("rewards accrued separate", rewardsSeparate);
        console.log("XVS balance", reward.balanceOf(address(vault)));
        console.log("Ctoken balance", cToken.balanceOf(address(vault)));

        console.log("--------SECOND ROLL FORK--------");

        vm.rollFork(25_691_325);
        assert(vm.isPersistent(address(comptroller)));
        totalAssets = vault.totalAssets();
        console.log("totalAssets second roll", totalAssets);
        console.log("block number", block.number);
        rewardsSeparate = comptroller.venusAccrued(address(vault));
        console.log("rewards accrued separate", rewardsSeparate);
        console.log("XVS balance", reward.balanceOf(address(comptroller)));
        console.log("Ctoken balance", cToken.balanceOf(address(vault)));

        console.log("--------HARVEST CALL--------");

        vault.harvest(0);

        assertEq(reward.balanceOf(address(vault)), 0);
        assertGe(vault.totalAssets(), totalAssets);

        rewardsSeparate = comptroller.venusAccrued(address(vault));
        console.log("rewards accrued separate final", rewardsSeparate);
        console.log("totalAssets after harvest", vault.totalAssets());
    }
}
