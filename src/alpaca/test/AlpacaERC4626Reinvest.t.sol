/// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {AlpacaERC4626Reinvest} from "../AlpacaERC4626Reinvest.sol";

import {IBToken} from "../interfaces/IBToken.sol";
import {IFairLaunch} from "../interfaces/IFairLaunch.sol";

/// Deployment addresses: https://github.com/alpaca-finance/bsc-alpaca-contract/blob/main/.mainnet.json
contract AlpacaERC4626ReinvestTest is Test {
    uint256 public bscFork;
    address public manager;
    address public alice;

    string BSC_RPC_URL = vm.envString("BSC_RPC_URL");

    AlpacaERC4626Reinvest public vault;

    IBToken public token = IBToken(0x7C9e73d4C71dae564d41F78d56439bB4ba87592f); /// @dev ibBUSD
    IFairLaunch public fairLaunch = IFairLaunch(0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F); /// @dev Same addr accross impls

    uint256 poolId = 3; /// @dev Check mainnet.json for poolId
    ERC20 public asset; /// @dev BUSD from ib(Token)

    ERC20 public alpacaToken = ERC20(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F); /// @dev AlpacaToken (reward token)
    address swapPair1 = 0x7752e1FA9F3a2e860856458517008558DEb989e3; /// ALPACA / BUSD

    function setUp() public {
        bscFork = vm.createFork(BSC_RPC_URL);
        vm.selectFork(bscFork);

        manager = msg.sender;
        alice = address(0x1);

        /// @dev Create ibBUSD vault with BUSD as underlying, of poolId 3
        setVault(token, poolId);

        /// @dev If ibBUSD is underlying, there's a direct pair available
        vm.prank(manager);
        vault.setRoute(address(asset), swapPair1, swapPair1);

        deal(address(asset), alice, 100000000 ether);
    }

    function setVault(IBToken asset_, uint256 poolId_) public {
        vm.startPrank(manager);

        token = asset_;
        asset = ERC20(token.token());
        poolId = poolId_;

        vault = new AlpacaERC4626Reinvest(token, fairLaunch, poolId_);

        vm.stopPrank();
    }

    function testDepositWithdraw() public {
        uint256 amount = 10000 ether;

        vm.startPrank(alice);
        
        uint256 aliceUnderlyingAmount = amount;
        
        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);

        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vault.withdraw(aliceAssetsToWithdraw, alice, alice);      
    }

    function testHarvest() public {
        uint256 amount = 10000 ether;

        vm.startPrank(alice);
        
        uint256 aliceUnderlyingAmount = amount;
        
        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        /// @dev temp hack to get ALPACA, impl should be tested more anyways
        deal(address(alpacaToken), address(vault), 100000 ether);
        vault.harvest(1);
    }

}
