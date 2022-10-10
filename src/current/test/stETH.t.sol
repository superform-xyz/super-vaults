// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {StETHERC4626} from "../eth-staking/stETH.sol";

interface IStETH {
    function getTotalShares() external view returns (uint256);

    function submit(address) external payable returns (uint256);

    function burnShares(address, uint256) external returns (uint256);

    function approve(address, uint256) external returns (bool);
}

interface wstETH {
    function wrap(uint256) external returns (uint256);

    function unwrap(uint256) external returns (uint256);

    function getStETHByWstETH(uint256) external view returns (uint256);

    function balanceOf(address) external view returns (uint256);
}

interface IWETH {
    function approve(address, uint256) external returns (bool);

    function balanceOf(address) external returns (uint256);

    function allowance(address, address) external returns (uint256);

    function wrap(uint256) external payable returns (uint256);

    function unwrap(uint256) external returns (uint256);
}

contract stEthTest is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    StETHERC4626 public vault;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    address public alice;
    address public manager;

    IWETH public _weth = IWETH(weth);
    IStETH public _stEth = IStETH(stEth);
    wstETH public _wstEth = wstETH(wstEth);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);
        vault = new StETHERC4626(weth, stEth, wstEth);
        alice = address(0x1);
        manager = msg.sender;

        /// Seed Vault with init deposit() to hack around rebasing stEth <> wstEth underlying
        /// wstEth balance on first deposit() is zero, user gets 100 shares, equal 1:1 with underlying
        deal(weth, alice, ONE_THOUSAND_E18);
        deal(weth, manager, ONE_THOUSAND_E18);

        vm.prank(manager);
        _weth.approve(address(vault), HUNDRED_E18);
        
        vm.prank(manager);
        vault.deposit(HUNDRED_E18, manager);
    }

    function testDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = HUNDRED_E18;

        vm.prank(alice);
        _weth.approve(address(vault), aliceUnderlyingAmount);
        assertEq(_weth.allowance(alice, address(vault)), aliceUnderlyingAmount);
        
        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        console.log("aliceShareAmount", aliceShareAmount);
        uint256 aliceAssetsFromShares = vault.convertToAssets(aliceShareAmount);
        console.log("aliceAssetsFromShares", aliceAssetsFromShares);

        vm.prank(alice);
        /// This returns 99.06 from 100 eth deposited
        vault.withdraw(aliceAssetsFromShares, alice, alice);

    }

}
