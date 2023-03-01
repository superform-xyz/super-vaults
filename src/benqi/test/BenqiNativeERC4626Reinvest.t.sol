// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {BenqiNativeERC4626Reinvest} from "../BenqiNativeERC4626Reinvest.sol";

import {ICEther} from "../compound/ICEther.sol";
import {IComptroller} from "../compound/IComptroller.sol";

contract BenqiNativeERC4626ReinvestTest is Test {
    address public manager;
    address public alice;
    address public bob;

    uint256 public ethFork;
    uint256 public ftmFork;
    uint256 public avaxFork;
    uint256 public polyFork;

    string ETH_RPC_URL = vm.envString("ETHEREUM_RPC_URL");
    string FTM_RPC_URL = vm.envString("FANTOM_RPC_URL");
    string AVAX_RPC_URL = vm.envString("AVALANCHE_RPC_URL");
    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");

    BenqiNativeERC4626Reinvest public vault;
    ERC20 public asset;
    ERC20 public reward;
    ICEther public cToken;
    IComptroller public comptroller;

    constructor() {
        avaxFork = vm.createFork(AVAX_RPC_URL);
        vm.selectFork(avaxFork);
        vm.roll(12649496);
        manager = msg.sender;
        comptroller = IComptroller(vm.envAddress("BENQI_COMPTROLLER"));

        /// Set vault as fallback
        setVault(
            ERC20(vm.envAddress("BENQI_WAVAX_ASSET")),
            ERC20(vm.envAddress("BENQI_REWARD_QI")),
            ICEther(vm.envAddress("BENQI_WAVAX_CETHER")),
            comptroller
        );

        asset = ERC20(vm.envAddress("BENQI_WAVAX_ASSET"));
        reward = ERC20(vm.envAddress("BENQI_REWARD_QI"));
        cToken = ICEther(vm.envAddress("BENQI_WAVAX_CETHER"));
    }

    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        hoax(alice, 1000 ether);
        deal(address(asset), alice, 100000000 ether);
        deal(address(asset), bob, 100000000 ether);
    }

    function setVault(
        ERC20 underylyingAsset,
        ERC20 reward_,
        ICEther cToken_,
        IComptroller comptroller_
    ) public {
        vm.startPrank(manager);

        asset = underylyingAsset;
        reward = reward;
        cToken = cToken_;

        vault = new BenqiNativeERC4626Reinvest(
            underylyingAsset,
            reward_,
            cToken_,
            manager
        );

        vm.stopPrank();
    }

    function testDepositWithdraw() public {
        uint256 amount = 1000000 ether;

        vm.startPrank(alice);
        uint256 aliceUnderlyingAmount = amount;

        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        
        uint256 preWithdrawBalance = asset.balanceOf(alice);
        uint256 sharesBurned = vault.withdraw(aliceAssetsToWithdraw, alice, alice);
        uint256 totalBalance = aliceAssetsToWithdraw + preWithdrawBalance;

        assertEq(totalBalance, asset.balanceOf(alice));
        assertEq(aliceShareAmount, sharesBurned);
        assertEq(vault.balanceOf(alice), 0);        
    }

    function testDepositWithdrawAVAX() public {
        uint256 amount = 100 ether;

        vm.prank(alice);
        uint256 aliceUnderlyingAmount = amount;

        uint256 aliceShareAmount = vault.deposit{value: aliceUnderlyingAmount}(
            alice
        );

        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vm.prank(alice);
        vault.withdraw(aliceAssetsToWithdraw, alice, alice);
    }
}
