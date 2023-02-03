// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {CompoundV3ERC4626Wrapper} from "../CompoundV3ERC4626Wrapper.sol";
import {CometMainInterface} from "../compound/IComet.sol";
import {ICometRewards} from "../compound/ICometRewards.sol";

contract CompoundV3ERC4626Test is Test {
    uint256 public ethFork;

    address public alice;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    CompoundV3ERC4626Wrapper public vault;

    ERC20 public asset = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    CometMainInterface public cToken = CometMainInterface(0xc3d688B66703497DAA19211EEdff47f25384cdc3);
    ICometRewards public rewardsManager =
        ICometRewards(0x1B0e765F6224C21223AeA2af16c1C46E38885a40);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);
        vault = new CompoundV3ERC4626Wrapper(
            asset,
            cToken,
            rewardsManager,
            msg.sender
        );

        alice = address(0x1);
        deal(address(asset), alice, 1000 ether);
    }

    function testDepositWithdraw() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        
        uint256 aliceUnderlyingAmount = amount;
        
        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);
        console.log("aliceUnderlyingAmount", aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        vault.withdraw(aliceAssetsToWithdraw, alice, alice);
        console.log(asset.balanceOf(alice));
        assertEq(vault.balanceOf(alice), 0);   
        assertEq(vault.totalSupply(), 0);  
    }

        function testDepositWithdrawWithInterest() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);
        
        uint256 aliceUnderlyingAmount = amount;
        
        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);
        console.log("aliceUnderlyingAmount", aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        // warp to make the account accrue some interest
        vm.warp( block.timestamp + 100 days);
        vault.redeem(aliceShareAmount, alice, alice);
        console.log(asset.balanceOf(alice));
        assertEq(vault.balanceOf(alice), 0);   
        assertEq(vault.totalSupply(), 0);  
    }

    // function testHarvest() public {
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
