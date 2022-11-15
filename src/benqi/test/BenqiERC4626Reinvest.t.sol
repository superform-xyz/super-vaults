// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {BenqiERC4626Reinvest} from "../BenqiERC4626Reinvest.sol";

import {ICERC20} from "../compound/ICERC20.sol";
import {IComptroller} from "../compound/IComptroller.sol";

contract BenqiERC4626ReinvestTest is Test {

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

    BenqiERC4626Reinvest public vault;
    ERC20 public asset;
    ERC20 public reward;
    ICERC20 public cToken;
    IComptroller public comptroller;

    constructor() {
        avaxFork = vm.createFork(AVAX_RPC_URL, 15_171_037);
        vm.selectFork(avaxFork);
        manager = msg.sender;
        comptroller = IComptroller(vm.envAddress("BENQI_COMPTROLLER"));

        /// Set vault as fallback
        setVault(
            ERC20(vm.envAddress("BENQI_USDC_ASSET")),
            ERC20(vm.envAddress("BENQI_REWARD_QI")),
            ICERC20(vm.envAddress("BENQI_USDC_CTOKEN")),
            comptroller
        );

        /// Init USDC vault always as fallback
        asset = ERC20(vm.envAddress("BENQI_USDC_ASSET"));
        reward = ERC20(vm.envAddress("BENQI_REWARD_QI"));
        cToken = ICERC20(vm.envAddress("BENQI_USDC_CTOKEN"));
    }

    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 100000000 ether);
        deal(address(asset), bob, 100000000 ether);

    }

    function setVault(
        ERC20 underylyingAsset,
        ERC20 reward_,
        ICERC20 cToken_,
        IComptroller comptroller_
    ) public {
        vm.startPrank(manager);

        asset = underylyingAsset;
        reward = reward;
        cToken = cToken_;

        vault = new BenqiERC4626Reinvest(
            underylyingAsset,
            reward_,
            cToken_,
            comptroller_,
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

        /// TODO: check rewards accrued more reliably than through transfering tokens directly
        // console.log("rewardsAccrued", rewardsAccrued);
        // console.log(block.timestamp, block.number);
        // vm.warp(block.timestamp + 100000000);
        // console.log(block.timestamp, block.number);
        // rewardsAccrued = comptroller.rewardAccrued(1, address(vault));
        // console.log("rewardsAccruedPost", rewardsAccrued);
        //////////////////////////////////////////////////////////////

        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vm.prank(alice);
        vault.withdraw(aliceAssetsToWithdraw, alice, alice);      
    }

}
