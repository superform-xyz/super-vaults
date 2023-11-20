// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {kycDAO4626} from "../kycdao4626.sol";
import {IKycValidity} from "../interfaces/IKycValidity.sol";

contract kycDAO4626Test is Test {
    uint256 public polygonFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");

    kycDAO4626 public vault;

    address public wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public kycValidity = 0x205E10d3c4C87E26eB66B1B270b71b7708494dB9;
    address public kycNFTHolder = 0x4f52d5D407e15c8b936302365cD84011a15284F2;

    address public alice;
    address public manager;

    ERC20 public _wmatic = ERC20(wmatic);
    IKycValidity public _kycValidity = IKycValidity(kycValidity);

    function setUp() public {
        polygonFork = vm.createFork(POLYGON_RPC_URL);
        vm.selectFork(polygonFork);

        vault = new kycDAO4626(_wmatic, kycValidity);
        alice = address(0x1);
        manager = msg.sender;

        deal(wmatic, kycNFTHolder, ONE_THOUSAND_E18);
        deal(wmatic, alice, ONE_THOUSAND_E18);
    }

    function testDepositWithdraw() public {
        uint256 underlyingAmount = 10_000_000_000_000_000;

        vm.startPrank(kycNFTHolder);

        _wmatic.approve(address(vault), underlyingAmount);
        assertEq(_wmatic.allowance(kycNFTHolder, address(vault)), underlyingAmount);

        uint256 expectedSharesFromAssets = vault.convertToShares(underlyingAmount);
        uint256 shareAmount = vault.deposit(underlyingAmount, kycNFTHolder);
        assertEq(expectedSharesFromAssets, shareAmount);

        uint256 assetsFromShares = vault.convertToAssets(shareAmount);

        vault.withdraw(assetsFromShares, kycNFTHolder, kycNFTHolder);
    }

    function testMintRedeem() public {
        uint256 sharesMint = 10_000_000_000_000_000;

        vm.startPrank(kycNFTHolder);

        uint256 expectedAssetFromShares = vault.convertToAssets(sharesMint);

        _wmatic.approve(address(vault), expectedAssetFromShares);

        uint256 assetAmount = vault.mint(sharesMint, kycNFTHolder);
        assertEq(expectedAssetFromShares, assetAmount);

        uint256 sharesAmount = vault.balanceOf(kycNFTHolder);
        assertEq(sharesAmount, sharesMint);

        vault.redeem(sharesAmount, kycNFTHolder, kycNFTHolder);
    }

    function testRevertDeposit() public {
        uint256 underlyingAmount = 10_000_000_000_000_000;

        vm.startPrank(alice);

        _wmatic.approve(address(vault), underlyingAmount);
        assertEq(_wmatic.allowance(alice, address(vault)), underlyingAmount);

        vm.expectRevert(kycDAO4626.NO_VALID_KYC_TOKEN.selector);
        vault.deposit(underlyingAmount, alice);
    }

    function testRevertMint() public {
        uint256 sharesMint = 10_000_000_000_000_000;

        vm.startPrank(alice);

        uint256 expectedAssetFromShares = vault.convertToAssets(sharesMint);

        _wmatic.approve(address(vault), expectedAssetFromShares);

        vm.expectRevert(kycDAO4626.NO_VALID_KYC_TOKEN.selector);
        vault.mint(sharesMint, alice);
    }
}
