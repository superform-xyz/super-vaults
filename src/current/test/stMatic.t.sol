// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {StMATIC4626} from "../token-staking/lido/stMATIC.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IStMATIC} from "../token-staking/interfaces/IStMATIC.sol";

contract stMaticTest is Test {
    uint256 public polygonFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string POLYGON_RPC_URL = vm.envString("POLYGON_MAINNET_RPC");

    StMATIC4626 public vault;

    address public matic = 0x0000000000000000000000000000000000001010;
    address public stMatic = 0x9ee91F9f426fA633d227f7a9b000E28b9dfd8599;

    address public alice;
    address public manager;

    ERC20 public _matic = ERC20(matic);
    IStMATIC public _stMatic = IStMATIC(stMatic);

    function setUp() public {
        polygonFork = vm.createFork(POLYGON_RPC_URL);
        vm.selectFork(polygonFork);

        vault = new StMATIC4626(matic, stMatic);
        alice = address(0x1);
        manager = msg.sender;

        /// [FAIL. Reason: Setup failed: stdStorage find(StdStorage): No storage use detected for target.]
        // deal(matic, alice, ONE_THOUSAND_E18);
        /// Lets prank then...
        
        vm.prank(0xd70250731A72C33BFB93016E3D1F0CA160dF7e42);
        _matic.transfer(alice, ONE_THOUSAND_E18);
        
    }

    function testDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = HUNDRED_E18;

        vm.startPrank(alice);
        console.log("alice bal matic", _matic.balanceOf(alice));

        // _matic.approve(address(vault), aliceUnderlyingAmount);
        // assertEq(_matic.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 expectedSharesFromAssets = vault.convertToShares(aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        assertEq(expectedSharesFromAssets, aliceShareAmount);
        console.log("aliceShareAmount", aliceShareAmount);

        uint256 aliceAssetsFromShares = vault.convertToAssets(aliceShareAmount);
        console.log("aliceAssetsFromShares", aliceAssetsFromShares);

        vault.withdraw(aliceAssetsFromShares, alice, alice);
    }

    // function testMintRedeem() public {
    //     uint256 aliceSharesMint = HUNDRED_E18;

    //     vm.startPrank(alice);

    //     uint256 expectedAssetFromShares = vault.convertToAssets(
    //         aliceSharesMint
    //     );

    //     _matic.approve(address(vault), expectedAssetFromShares);

    //     uint256 aliceAssetAmount = vault.mint(aliceSharesMint, alice);
    //     assertEq(expectedAssetFromShares, aliceAssetAmount);

    //     uint256 aliceSharesAmount = vault.balanceOf(alice);
    //     assertEq(aliceSharesAmount, aliceSharesMint);

    //     vault.redeem(aliceSharesAmount, alice, alice);
    // }

}
