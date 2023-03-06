// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {StETHERC4626Swap} from "../stETH_swap.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ICurve} from "../interfaces/ICurve.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {wstETH} from "../interfaces/wstETH.sol";

contract stEthSwapTest is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETHEREUM_RPC_URL");

    StETHERC4626Swap public vault;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public curvePool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    address public alice;
    address public bob;
    address public manager;

    IWETH public _weth = IWETH(weth);
    IStETH public _stEth = IStETH(stEth);
    ICurve public _curvePool = ICurve(curvePool);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);
        alice = address(0x1);
        bob = address(0x2);
        manager = msg.sender;

        vault = new StETHERC4626Swap(weth, stEth, curvePool, manager);

        deal(weth, alice, ONE_THOUSAND_E18);
        deal(weth, bob, ONE_THOUSAND_E18);
        deal(weth, manager, ONE_THOUSAND_E18);
    }

    function testDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = HUNDRED_E18;
        uint256 bobUnderlyingAmount = 1000;

        vm.startPrank(bob);
        _weth.approve(address(vault), bobUnderlyingAmount);
        vault.deposit(bobUnderlyingAmount, bob);
        vm.stopPrank();

        vm.startPrank(alice);

        _weth.approve(address(vault), aliceUnderlyingAmount);
        assertEq(_weth.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        console.log("aliceShareAmount", aliceShareAmount);

        uint256 aliceAssetsFromShares = vault.convertToAssets(aliceShareAmount);
        console.log("aliceAssetsFromShares", aliceAssetsFromShares);

        vault.withdraw(aliceAssetsFromShares, alice, alice);
    }

}
