// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {rEthERC4626} from "../rEth.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IRETH} from "../interfaces/IReth.sol";
import {IRSTORAGE} from "../interfaces/IRstorage.sol";
import {IWETH} from "../interfaces/IWETH.sol";

contract rEthTest is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETHEREUM_RPC_URL");

    rEthERC4626 public vault;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public rStorage = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;

    address public alice;
    address public manager;

    IWETH public _weth = IWETH(weth);
    IRETH public _rEth;
    IRSTORAGE public _rStorage = IRSTORAGE(rStorage);

    /// https://docs.rocketpool.net/overview/contracts-integrations/#protocol-contracts
    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        
        /// @dev Set the block with freeSlots available to deposit
        vm.rollFork(ethFork, 15_565_892);
        vm.selectFork(ethFork);

        address rocketDepositPoolAddress = _rStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
        );

        _rEth = IRETH(rocketDepositPoolAddress);

        vault = new rEthERC4626(weth, rStorage);
        alice = address(0x1);
        manager = msg.sender;

        deal(weth, alice, ONE_THOUSAND_E18);
    }

    function testDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = 1 ether;

        vm.startPrank(alice);

        _weth.approve(address(vault), aliceUnderlyingAmount);
        assertEq(_weth.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 expectedSharesFromAssets = vault.convertToShares(
            aliceUnderlyingAmount
        );

        console.log("expectedSharesFromAssets", expectedSharesFromAssets);
   
        /// @dev Set the block with freeSlots available to deposit
        assertEq(block.number, 15_565_892);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        assertEq(expectedSharesFromAssets, aliceShareAmount);
        console.log("aliceShareAmount", aliceShareAmount);

        /// @dev Caller asks to withdraw ETH asset equal to the vrETH he owns
        uint256 aliceAssetsFromShares = vault.previewRedeem(aliceShareAmount);
        uint256 aliceRethBalance = vault.balanceOf(alice);

        if (aliceRethBalance > aliceAssetsFromShares) {
            console.log("aliceAssetsFromShares", aliceAssetsFromShares);
            vault.withdraw(aliceAssetsFromShares, alice, alice);
        } else {
            uint256 aliceMaxWithdraw = vault.maxWithdraw(alice);
            console.log("aliceMaxWithdraw", aliceMaxWithdraw);
            vault.withdraw(aliceMaxWithdraw, alice, alice);
        }

    }

    function testMintRedeem() public {
        uint256 aliceSharesMint = 1 ether;

        vm.startPrank(alice);

        /// how much eth-backing we'll get for this amount of rEth
        /// previewMint should return amount of weth to supply for asked vrEth shares
        uint256 expectedAssetFromShares = vault.previewMint(
            aliceSharesMint /// vrEth amount (caller wants 1e18 vrEth : rEth)
        );

        console.log("expectedAssetFromShares", expectedAssetFromShares);

        _weth.approve(address(vault), expectedAssetFromShares);

        uint256 aliveRethMinted = vault.mint(aliceSharesMint, alice);
        
        console.log("aliceAssetAmount", aliveRethMinted);

        // assertEq(expectedAssetFromShares, aliceAssetAmount);
        
        uint256 aliceEthToRedeem = vault.previewRedeem(aliveRethMinted);
        uint256 aliceRethBalance = vault.balanceOf(alice);

        console.log("aliceSharesAmount", aliceRethBalance);

        // assertEq(aliceSharesAmount, aliceSharesMint);

        /// @dev Caller asks to withdraw ETH asset equal to the vrETH he owns
        if (aliceRethBalance > aliceEthToRedeem) {
            console.log("aliceAssetsFromShares", aliceEthToRedeem);
            vault.redeem(aliceEthToRedeem, alice, alice);
        } else {
            uint256 aliceMaxRedeem = vault.maxRedeem(alice);
            console.log("aliceMaxRedeem", aliceMaxRedeem);
            vault.redeem(aliceMaxRedeem, alice, alice);
        }

    }
}
