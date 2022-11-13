// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {BenqiERC4626Reinvest} from "../BenqiERC4626Reinvest.sol";
import {ICERC20} from "../compound/ICERC20.sol";
import {IComptroller} from "../compound/IComptroller.sol";

contract BenqiERC4626ReinvestTest is Test {
    uint256 public ethFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    BenqiERC4626Reinvest public vault;

    ERC20 public asset = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public reward = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ICERC20 public cToken = ICERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    IComptroller public comptroller =
        IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);
        vault = new BenqiERC4626Reinvest(
            asset,
            reward,
            cToken,
            comptroller,
            msg.sender
        );
    }

    function testDepositWithdraw() public {
        uint256 amount = 100 ether;

        address alice = address(0x616eFd3E811163F8fc180611508D72D842EA7D07);
        vm.prank(alice);
        
        uint256 aliceUnderlyingAmount = amount;
        
        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vm.prank(alice);
        vault.withdraw(aliceAssetsToWithdraw, alice, alice);      
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
