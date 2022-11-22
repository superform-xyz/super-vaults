// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

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

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");
    string FTM_RPC_URL = vm.envString("FTM_MAINNET_RPC");
    string AVAX_RPC_URL = vm.envString("AVAX_MAINNET_RPC");
    string POLYGON_MAINNET_RPC = vm.envString("POLYGON_MAINNET_RPC");

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

        vm.prank(alice);        
        uint256 aliceUnderlyingAmount = amount;
        
        asset.approve(address(vault), aliceUnderlyingAmount);
        assertEq(asset.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 alicePreDepositBal = asset.balanceOf(alice);

        vm.prank(alice);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        uint256 rewardsAccrued = comptroller.rewardAccrued(1, address(vault));

        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vm.prank(alice);
        vault.withdraw(aliceAssetsToWithdraw, alice, alice);      
    }

    function testDepositWithdrawAVAX() public {
        uint256 amount = 100 ether;

        vm.prank(alice);        
        uint256 aliceUnderlyingAmount = amount;

        uint256 aliceShareAmount = vault.deposit{value: aliceUnderlyingAmount}(alice);

        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vm.prank(alice);
        vault.withdraw(aliceAssetsToWithdraw, alice, alice);      
    }

}
