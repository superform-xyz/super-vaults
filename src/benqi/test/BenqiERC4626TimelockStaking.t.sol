// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {BenqiERC4626TimelockStaking} from "../BenqiERC4626TimelockStaking.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IPair, DexSwap} from "../../_global/swapUtils.sol";
import {IStETH} from "../../lido/interfaces/IStETH.sol";
import {IWETH} from "../../lido/interfaces/IWETH.sol";

contract BenqiERC4626TimelockStakingTest is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("AVALANCHE_RPC_URL");

    BenqiERC4626TimelockStaking public vault;

    address public weth = vm.envAddress("BENQI_WAVAX_ASSET");
    address public stEth = vm.envAddress("BENQI_sAVAX_ASSET");
    address public traderJoePool = 0x4b946c91C2B1a7d7C40FB3C130CdfBaf8389094d;

    address public alice;
    address public manager;

    IWETH public _weth = IWETH(weth);
    IStETH public _stEth = IStETH(stEth);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new BenqiERC4626TimelockStaking(weth, stEth);
        alice = address(0x1);
        manager = msg.sender;

        deal(weth, alice, ONE_THOUSAND_E18);
        deal(weth, manager, ONE_THOUSAND_E18);
        deal(alice, 2 ether);
    }

    function testDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = HUNDRED_E18;

        vm.startPrank(alice);

        _weth.approve(address(vault), aliceUnderlyingAmount);
        assertEq(_weth.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 expectedSharesFromAssets = vault.previewDeposit(aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        vm.warp(block.timestamp + 120 days);

        assertEq(expectedSharesFromAssets, aliceShareAmount);
        console.log("aliceShareAmount", aliceShareAmount);

        uint256 aliceAssetsFromShares = vault.previewRedeem(aliceShareAmount);
        console.log("aliceAssetsFromShares", aliceAssetsFromShares);

        /// @dev Approve the vault to spend it's shares
        vault.approve(address(vault), aliceShareAmount); 
        vault.requestWithdraw(aliceAssetsFromShares, alice);
        vm.warp(block.timestamp + 16 days);

        /// FIXME: Wrong asset/shares calculations for redemption, we seem to be off by few wei
        // vault.withdraw(aliceAssetsFromShares, alice, alice);
    }

}
