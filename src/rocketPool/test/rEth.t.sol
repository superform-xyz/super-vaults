// SPDX-License-Identifier: UNLICENSED
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

    /// Expect Error: The deposit pool size after depositing exceeds the maximum size
    /// That's because RocketPool only allows staking if slots are free.
    function testDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = 10000000000000000;

        vm.startPrank(alice);
        console.log("alice bal weth", _weth.balanceOf(alice));

        _weth.approve(address(vault), aliceUnderlyingAmount);
        assertEq(
            _weth.allowance(alice, address(vault)),
            aliceUnderlyingAmount
        );

        uint256 expectedSharesFromAssets = vault.convertToShares(
            aliceUnderlyingAmount
        );
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        assertEq(expectedSharesFromAssets, aliceShareAmount);
        console.log("aliceShareAmount", aliceShareAmount);

        uint256 aliceAssetsFromShares = vault.convertToAssets(aliceShareAmount);
        console.log("aliceAssetsFromShares", aliceAssetsFromShares);

        vault.withdraw(aliceAssetsFromShares, alice, alice);
    }

    /// Expect Error: The deposit pool size after depositing exceeds the maximum size
    /// That's because RocketPool only allows staking if slots are free.
    function testMintRedeem() public {
        uint256 aliceSharesMint = 10000000000000000;

        vm.startPrank(alice);

        uint256 expectedAssetFromShares = vault.convertToAssets(
            aliceSharesMint
        );

        _weth.approve(address(vault), expectedAssetFromShares);

        uint256 aliceAssetAmount = vault.mint(aliceSharesMint, alice);
        assertEq(expectedAssetFromShares, aliceAssetAmount);

        uint256 aliceSharesAmount = vault.balanceOf(alice);
        assertEq(aliceSharesAmount, aliceSharesMint);

        vault.redeem(aliceSharesAmount, alice, alice);
    }
}
