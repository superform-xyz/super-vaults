// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {AaveV2StrategyWrapper} from "../aave-v2/AaveV2StrategyWrapper.sol";
import {IMultiFeeDistribution} from "../utils/aave/IMultiFeeDistribution.sol";
import {ILendingPool} from "../utils/aave/ILendingPool.sol";

contract AaveV2StrategyWrapperTest is Test {
    uint256 public ethFork;
    uint256 public ftmFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");
    string FTM_RPC_URL = vm.envString("FTM_MAINNET_RPC");

    AaveV2StrategyWrapper public vault;

    /// Fantom's Geist Forked AAVE-V2 Protocol DAI Pool Config
    ERC20 public underlying = ERC20(0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E); /// DAI
    ERC20 public aToken = ERC20(0x07E6332dD090D287d3489245038daF987955DCFB); // gDAI
    IMultiFeeDistribution public rewards = IMultiFeeDistribution(0x49c93a95dbcc9A6A4D8f77E59c038ce5020e82f8);
    ILendingPool public lendingPool = ILendingPool(0x9FAD24f572045c7869117160A571B2e50b10d068);
    address rewardToken = 0xd8321AA83Fb0a4ECd6348D4577431310A6E0814d;
    
    function setUp() public {
        ftmFork = vm.createFork(FTM_RPC_URL);
        vm.selectFork(ftmFork);
        vault = new AaveV2StrategyWrapper(
            underlying,
            aToken,
            rewards,
            lendingPool,
            rewardToken,
            msg.sender
        );
    }

    function testSingleDepositWithdraw() public {
        uint256 amount = 100 ether;

        uint256 aliceUnderlyingAmount = amount;

        address alice = address(0x1cA60862a771f1F47d94F87bebE4226141b19C9c);
        vm.prank(alice);

        underlying.approve(address(vault), aliceUnderlyingAmount);
        assertEq(underlying.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 alicePreDepositBal = underlying.balanceOf(alice);
        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        // Expect exchange rate to be 1:1 on initial deposit.
        // assertEq(aliceUnderlyingAmount, aliceShareAmount);
        // assertEq(vault.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
        // assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        // assertEq(vault.totalSupply(), aliceShareAmount);
        // assertEq(vault.totalAssets(), aliceUnderlyingAmount);
        // assertEq(vault.balanceOf(alice), aliceShareAmount);
        // assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceUnderlyingAmount);
        // assertEq(underlying.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

        vm.prank(alice);
        vault.withdraw(aliceUnderlyingAmount, alice, alice);

        // assertEq(vault.totalAssets(), 0);
        // assertEq(vault.balanceOf(alice), 0);
        // assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        // assertEq(underlying.balanceOf(alice), alicePreDepositBal);
    }


    // function testSingleMintRedeem(uint128 amount) public {
    //     if (amount == 0) {
    //         amount = 100e18;
    //     }

    //     uint256 aliceShareAmount = amount;

    //     address alice = address(0xABCD);

    //     // underlying.mint(alice, aliceShareAmount);

    //     vm.prank(alice);
    //     underlying.approve(address(vault), aliceShareAmount);
    //     assertEq(underlying.allowance(alice, address(vault)), aliceShareAmount);

    //     uint256 alicePreDepositBal = underlying.balanceOf(alice);

    //     vm.prank(alice);
    //     uint256 aliceUnderlyingAmount = vault.mint(aliceShareAmount, alice);

    //     // Expect exchange rate to be 1:1 on initial mint.
    //     assertEq(aliceShareAmount, aliceUnderlyingAmount);
    //     assertEq(vault.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
    //     assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
    //     assertEq(vault.totalSupply(), aliceShareAmount);
    //     assertEq(vault.totalAssets(), aliceUnderlyingAmount);
    //     assertEq(vault.balanceOf(alice), aliceUnderlyingAmount);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), aliceUnderlyingAmount);
    //     assertEq(underlying.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

    //     vm.prank(alice);
    //     vault.redeem(aliceShareAmount, alice, alice);

    //     assertEq(vault.totalAssets(), 0);
    //     assertEq(vault.balanceOf(alice), 0);
    //     assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
    //     assertEq(underlying.balanceOf(alice), alicePreDepositBal);
    // }
}
