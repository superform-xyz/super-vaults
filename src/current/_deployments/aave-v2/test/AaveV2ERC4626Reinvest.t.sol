// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {AaveV2ERC4626Reinvest} from "../AaveV2ERC4626Reinvest.sol";
import {AaveV2ERC4626ReinvestFactory} from "../AaveV2ERC4626ReinvestFactory.sol";

import {ILendingPool} from "../aave/ILendingPool.sol";
import {IAaveMining} from "../aave/IAaveMining.sol";
import {DexSwap} from "../../../utils/swapUtils.sol";

contract AaveV2ERC4626ReinvestTest is Test {
    address public manager;
    address public alice;

    uint256 public ethFork;
    uint256 public ftmFork;
    uint256 public avaxFork;
    uint256 public polyFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");
    string FTM_RPC_URL = vm.envString("FTM_MAINNET_RPC");
    string AVAX_RPC_URL = vm.envString("AVAX_MAINNET_RPC");
    string POLYGON_MAINNET_RPC = vm.envString("POLYGON_MAINNET_RPC");

    AaveV2ERC4626Reinvest public vault;
    AaveV2ERC4626ReinvestFactory public factory;

    ERC20 public asset;
    ERC20 public aToken;
    IAaveMining public rewards;
    ILendingPool public lendingPool;
    address public rewardToken;

    constructor() {

        ethFork = vm.createFork(POLYGON_MAINNET_RPC); /// @dev No rewards on ETH mainnet
        ftmFork = vm.createFork(POLYGON_MAINNET_RPC);  /// @dev No rewards on FTM
        avaxFork = vm.createFork(POLYGON_MAINNET_RPC); /// @dev No rewards on Avax

        /// @dev V2 makes sense only on Polygon (TVL)
        polyFork = vm.createFork(POLYGON_MAINNET_RPC); /// @dev No rewards on Polygon

        manager = msg.sender;

        vm.selectFork(polyFork);

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

        (ERC4626 v, AaveV2ERC4626Reinvest v_) = setVault(
            ERC20(vm.envAddress("AAVEV2_POLYGON_DAI"))
        );
        vault = v_;
    }

    function setVault(
        ERC20 _asset
    ) public returns (ERC4626 vault_, AaveV2ERC4626Reinvest _vault_) {
        asset = _asset;

        /// @dev If we need strict ERC4626 interface
        vault_ = factory.createERC4626(asset);

        /// @dev If we need to use the AaveV2ERC4626Reinvest interface with harvest
        _vault_ = AaveV2ERC4626Reinvest(address(vault_));
    }

    function setUp() public {
        alice = address(0x1);
        deal(address(asset), alice, 10000 ether);
    }

    function makeDeposit() public returns (uint256 shares) {
        vm.startPrank(alice);
        uint256 amount = 100 ether;

        uint256 aliceUnderlyingAmount = amount;

        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        shares = vault.deposit(aliceUnderlyingAmount, alice);
        vm.stopPrank();
    }

    function testFactoryDeploy() public {
        vm.startPrank(manager);
        
        /// @dev We deploy with different asset than in constructor
        ERC4626 vault_ = factory.createERC4626(ERC20(vm.envAddress("AAVEV2_POLYGON_WMATIC")));
        ERC20 vaultAsset = vault_.asset();
        
        vm.stopPrank();
        vm.startPrank(alice);

        /// @dev Just check if we can deposit
        uint256 amount = 100 ether;
        deal(address(vaultAsset), alice, 10000 ether);
        uint256 aliceUnderlyingAmount = amount;
        vaultAsset.approve(address(vault_), aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault_.deposit(aliceUnderlyingAmount, alice);
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

    /// @dev WARN: Error here because we changed the implementation of harvest
    /// You can only test now with aave, not geist, which implements curve-style rewards
    // function testHarvester() public {
    //     uint256 aliceShareAmount = makeDeposit();

    //     assertEq(vault.totalSupply(), aliceShareAmount);
    //     assertEq(vault.totalAssets(), 100 ether);
    //     console.log("totalAssets before harvest", vault.totalAssets());

    //     assertEq(ERC20(rewardToken).balanceOf(address(vault)), 1000 ether);
    //     vault.harvest();
    //     assertEq(ERC20(rewardToken).balanceOf(address(vault)), 0);
    //     console.log("totalAssets after harvest", vault.totalAssets());
    // }
}
