// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {AaveV2ERC4626Reinvest} from "../AaveV2ERC4626Reinvest.sol";
import {AaveV2ERC4626ReinvestFactory} from "../AaveV2ERC4626ReinvestFactory.sol";

import {ILendingPool} from "../aave/ILendingPool.sol";
import {IAaveMining} from "../aave/IAaveMining.sol";
import {DexSwap} from "../../_global/swapUtils.sol";

contract AaveV2ERC4626ReinvestTest is Test {
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

    AaveV2ERC4626Reinvest public vault;
    AaveV2ERC4626ReinvestFactory public factory;

    ERC20 public asset;
    ERC20 public aToken;
    IAaveMining public rewards;
    ILendingPool public lendingPool;
    address public rewardToken;

    ////////////////////////////////////////
    constructor() {
        ethFork = vm.createFork(POLYGON_RPC_URL);
        /// @dev No rewards on ETH mainnet
        ftmFork = vm.createFork(POLYGON_RPC_URL);
        /// @dev No rewards on FTM
        avaxFork = vm.createFork(POLYGON_RPC_URL);
        /// @dev No rewards on Avax

        /// @dev Use Polygon Fork
        polyFork = vm.createFork(POLYGON_RPC_URL);
        /// @dev No rewards on Polygon

        manager = msg.sender;

        vm.selectFork(polyFork);
        vm.rollFork(39700000);

        /// @dev Original AAVE v2 reward mining is disabled on each network
        /// @dev We can leave this set to whatever on V2, harvest() is just not used
        rewards = IAaveMining(vm.envAddress("AAVEV2_POLYGON_REWARDS"));
        rewardToken = vm.envAddress("AAVEV2_POLYGON_REWARDTOKEN");

        lendingPool = ILendingPool(vm.envAddress("AAVEV2_POLYGON_LENDINGPOOL"));

        factory = new AaveV2ERC4626ReinvestFactory(
            rewards,
            lendingPool,
            rewardToken,
            manager
        );

        (, AaveV2ERC4626Reinvest v_) = setVault(ERC20(vm.envAddress("AAVEV2_POLYGON_DAI")));

        vault = v_;
    }

    function setVault(ERC20 _asset) public returns (ERC4626 vault_, AaveV2ERC4626Reinvest _vault_) {
        vm.startPrank(manager);

        asset = _asset;

        /// @dev If we need strict ERC4626 interface
        vault_ = factory.createERC4626(asset);

        /// @dev If we need to use the AaveV2ERC4626Reinvest interface with harvest
        _vault_ = AaveV2ERC4626Reinvest(address(vault_));

        vm.stopPrank();
    }

    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 10000 ether);
        deal(address(asset), bob, 10000 ether);
    }

    function testFactoryDeploy() public {
        vm.startPrank(manager);

        /// @dev We deploy with different asset than at runtime (constructor)
        ERC4626 v_ = factory.createERC4626(ERC20(vm.envAddress("AAVEV2_POLYGON_WMATIC")));
        ERC20 vaultAsset = v_.asset();

        AaveV2ERC4626Reinvest vault_ = AaveV2ERC4626Reinvest(address(v_));

        factory.setRoute(vault_, address(0x11), address(0x12), address(0x13));

        vm.stopPrank();
        vm.startPrank(alice);

        /// @dev Just check if we can deposit
        uint256 amount = 100 ether;
        deal(address(vaultAsset), alice, 10000 ether);
        uint256 aliceUnderlyingAmount = amount;
        vaultAsset.approve(address(vault_), aliceUnderlyingAmount);
        vault_.deposit(aliceUnderlyingAmount, alice);
    }

    function testFailManagerCreateERC4626() public {
        vm.startPrank(alice);
        factory.createERC4626(ERC20(vm.envAddress("AAVEV2_POLYGON_WMATIC")));
    }

    function testFailManagerSetRoute() public {
        vm.startPrank(alice);
        address swapToken = address(0x11);
        address pair1 = address(0x12);
        address pair2 = address(0x13);
        factory.setRoute(vault, swapToken, pair1, pair2);
        vm.stopPrank();

        vm.startPrank(manager);
        /// @dev Should fail because only Manager contract can be a setter, not manager itself
        vault.setRoute(swapToken, pair1, pair2);
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
}
