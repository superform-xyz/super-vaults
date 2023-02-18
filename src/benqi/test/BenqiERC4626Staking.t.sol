// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {BenqiERC4626Staking} from "../BenqiERC4626Staking.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IPair, DexSwap} from "../utils/swapUtils.sol";
import {IStETH} from "../../lido/interfaces/IStETH.sol";
import {IWETH} from "../../lido/interfaces/IWETH.sol";

contract BenqiERC4626StakingTest is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("AVALANCHE_RPC_URL");

    BenqiERC4626Staking public vault;

    address public weth = vm.envAddress("BENQI_WAVAX_ASSET");
    address public stEth = vm.envAddress("BENQI_sAVAX_ASSET");
    address public traderJoePool = 0x4b946c91C2B1a7d7C40FB3C130CdfBaf8389094d;

    address public alice;
    address public manager;

    IWETH public _weth = IWETH(weth);
    IStETH public _stEth = IStETH(stEth);
    IPair public _traderJoePool = IPair(traderJoePool);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new BenqiERC4626Staking(weth, stEth, traderJoePool);
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
        
        assertEq(expectedSharesFromAssets, aliceShareAmount);
        console.log("aliceShareAmount", aliceShareAmount);

        uint256 aliceAssetsFromShares = vault.previewRedeem(aliceShareAmount);
        console.log("aliceAssetsFromShares", aliceAssetsFromShares);

        vault.withdraw(aliceAssetsFromShares, alice, alice);
    }

    function testMintRedeem() public {
        uint256 aliceSharesMint = HUNDRED_E18;

        vm.startPrank(alice);

        uint256 expectedAssetFromShares = vault.previewMint(
            aliceSharesMint
        );

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
