// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {CompoundV2StrategyWrapper} from "../compound-v2/CompoundV2StrategyWrapper.sol";
import {ICERC20} from "../utils/compound/ICERC20.sol";
import {IComptroller} from "../utils/compound/IComptroller.sol";

contract CompoundV2StrategyWrapperTest is Test {
    uint256 public ethFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    CompoundV2StrategyWrapper public vault;

    ERC20 public asset = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public reward = ERC20(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    ICERC20 public cToken = ICERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    IComptroller public comptroller =
        IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);
        vault = new CompoundV2StrategyWrapper(
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
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        // vm.prank(alice);
        // vault.withdraw(aliceUnderlyingAmount, alice, alice);

        // assertEq(vault.totalAssets(), 0);
        // assertEq(vault.balanceOf(alice), 0);
        // assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        // assertEq(asset.balanceOf(alice), alicePreDepositBal);        
    }

    function testMintRedeem() public {}
}
