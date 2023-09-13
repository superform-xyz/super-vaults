// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {StETHERC4626} from "../stETH.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ICurve} from "../interfaces/ICurve.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {wstETH} from "../interfaces/wstETH.sol";

contract stEthTest is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETHEREUM_RPC_URL");

    StETHERC4626 public vault;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    address public alice;
    address public manager;

    IWETH public _weth = IWETH(weth);
    IStETH public _stEth = IStETH(stEth);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new StETHERC4626(weth, stEth);
        alice = address(0x1);
        manager = msg.sender;

        deal(weth, alice, ONE_THOUSAND_E18);
        deal(weth, manager, ONE_THOUSAND_E18);
    }

    function testDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = HUNDRED_E18;

        vm.startPrank(alice);

        _weth.approve(address(vault), aliceUnderlyingAmount);
        assertEq(_weth.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 expectedSharesFromAssets = vault.previewDeposit(aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        assertEq(expectedSharesFromAssets, aliceShareAmount);
        console.log("aliceShareAmount", aliceShareAmount);

        uint256 aliceAssetsFromShares = vault.previewRedeem(aliceShareAmount);
        console.log("aliceAssetsFromShares", aliceAssetsFromShares);

        vault.withdraw(aliceAssetsFromShares, alice, alice);
    }

    function testMintRedeem() public {
        uint256 aliceSharesMint = HUNDRED_E18;

        vm.startPrank(alice);

        uint256 expectedAssetFromShares = vault.previewMint(aliceSharesMint);

        console.log("expectedAssetFromShares (to approve)", expectedAssetFromShares);

        _weth.approve(address(vault), expectedAssetFromShares);

        uint256 aliceAssetAmount = vault.mint(aliceSharesMint, alice);
        console.log("aliceAssetAmount", aliceAssetAmount);
        assertEq(expectedAssetFromShares, aliceAssetAmount);

        uint256 aliceSharesAmount = vault.balanceOf(alice);
        console.log("aliceSharesAmount", aliceSharesAmount);

        uint256 sharesBurned = vault.redeem(aliceSharesAmount, alice, alice);
        console.log("sharesBurned", sharesBurned);
    }

    function testDepositETH() public {
        uint256 aliceEth = HUNDRED_E18;

        startHoax(alice, aliceEth + 1 ether);

        uint256 expectedSharesFromAsset = vault.convertToShares(aliceEth);
        uint256 aliceShareAmount = vault.deposit{value: aliceEth}(alice);
        assertEq(expectedSharesFromAsset, aliceShareAmount);
    }
}
