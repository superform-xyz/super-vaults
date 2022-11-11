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
    uint256 public ethFork;
    uint256 public ftmFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");
    string FTM_RPC_URL = vm.envString("FTM_MAINNET_RPC");

    AaveV2ERC4626Reinvest public vault;
    AaveV2ERC4626ReinvestFactory public factory;

    /// Fantom's Geist Forked AAVE-V2 Protocol DAI Pool Config
    ERC20 public underlying = ERC20(0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E); /// DAI
    ERC20 public aToken = ERC20(0x07E6332dD090D287d3489245038daF987955DCFB); // gDAI
    IAaveMining public rewards =
        IAaveMining(0x49c93a95dbcc9A6A4D8f77E59c038ce5020e82f8);
    ILendingPool public lendingPool =
        ILendingPool(0x9FAD24f572045c7869117160A571B2e50b10d068);
    address rewardToken = 0xd8321AA83Fb0a4ECd6348D4577431310A6E0814d;

    address public alice;

    function setUp() public {
        ftmFork = vm.createFork(FTM_RPC_URL);
        manager = msg.sender;
        console.log("manager", manager);
        vm.selectFork(ftmFork);

        factory = new AaveV2ERC4626ReinvestFactory(
            rewards,
            lendingPool,
            rewardToken,
            manager
        );

        vault = new AaveV2ERC4626Reinvest(
            underlying,
            aToken,
            rewards,
            lendingPool,
            rewardToken,
            manager
        );

        address swapToken = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83; /// FTM
        address swapPair1 = 0x668AE94D0870230AC007a01B471D02b2c94DDcB9; /// Geist - Ftm
        address swapPair2 = 0xe120ffBDA0d14f3Bb6d6053E90E63c572A66a428; /// Ftm - Dai
        vm.prank(manager);

        vault.setRoute(swapToken, swapPair1, swapPair2);

        /// Simulate rewards accrued to the vault contract
        alice = address(0x1);
        deal(rewardToken, address(vault), 1000 ether);
        deal(address(underlying), alice, 10000 ether);
    }

    function makeDeposit() public returns (uint256 shares) {
        vm.startPrank(alice);
        uint256 amount = 100 ether;

        uint256 aliceUnderlyingAmount = amount;

        underlying.approve(address(vault), aliceUnderlyingAmount);
        assertEq(
            underlying.allowance(alice, address(vault)),
            aliceUnderlyingAmount
        );

        shares = vault.deposit(aliceUnderlyingAmount, alice);
        vm.stopPrank();
    }

    function testFactoryDeploy() public {
        vm.startPrank(manager);
        ERC4626 vault_ = factory.createERC4626(underlying);
        vm.stopPrank();
        vm.startPrank(alice);

        uint256 amount = 100 ether;
        uint256 aliceUnderlyingAmount = amount;
        underlying.approve(address(vault_), aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault_.deposit(aliceUnderlyingAmount, alice);
    }

    function testSingleDepositWithdraw() public {
        vm.startPrank(alice);

        uint256 amount = 100 ether;

        uint256 aliceUnderlyingAmount = amount;

        underlying.approve(address(vault), aliceUnderlyingAmount);
        assertEq(
            underlying.allowance(alice, address(vault)),
            aliceUnderlyingAmount
        );

        uint256 alicePreDepositBal = underlying.balanceOf(alice);
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
            underlying.balanceOf(alice),
            alicePreDepositBal - aliceUnderlyingAmount
        );

        vault.withdraw(aliceUnderlyingAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(underlying.balanceOf(alice), alicePreDepositBal);
    }

    function testSingleMintRedeem() public {
        vm.startPrank(alice);

        uint256 amount = 100 ether;

        uint256 aliceShareAmount = amount;

        underlying.approve(address(vault), aliceShareAmount);
        assertEq(underlying.allowance(alice, address(vault)), aliceShareAmount);

        uint256 alicePreDepositBal = underlying.balanceOf(alice);

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
            underlying.balanceOf(alice),
            alicePreDepositBal - aliceUnderlyingAmount
        );

        vault.redeem(aliceShareAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(underlying.balanceOf(alice), alicePreDepositBal);
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
