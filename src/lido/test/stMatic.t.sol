// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { StMATIC4626 } from "../stMATIC.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { IStMATIC } from "../interfaces/IStMATIC.sol";
import { IWETH } from "../interfaces/IWETH.sol";

contract stMaticTest is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETHEREUM_RPC_URL");

    StMATIC4626 public vault;

    address public matic = 0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0;
    address public stMatic = 0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599;

    address public alice;
    address public manager;

    IStMATIC public _stMatic = IStMATIC(stMatic);
    ERC20 public _matic = ERC20(matic);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new StMATIC4626(matic, stMatic);
        alice = address(0x1);
        manager = msg.sender;

        deal(matic, alice, ONE_THOUSAND_E18);
    }

    function testDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = 1 ether;

        vm.startPrank(alice);
        console.log("alice bal matic", _matic.balanceOf(alice));

        _matic.approve(address(vault), aliceUnderlyingAmount);
        assertEq(_matic.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 expectedSharesFromAssets = vault.convertToShares(aliceUnderlyingAmount);
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

        _matic.approve(address(vault), expectedAssetFromShares);

        uint256 aliceAssetAmount = vault.mint(aliceSharesMint, alice);
        assertEq(expectedAssetFromShares, aliceAssetAmount);

        uint256 aliceSharesAmount = vault.balanceOf(alice);

        console.log("aliceSharesAmount", aliceSharesAmount);
        vault.redeem(aliceSharesAmount, alice, alice);
    }
}
