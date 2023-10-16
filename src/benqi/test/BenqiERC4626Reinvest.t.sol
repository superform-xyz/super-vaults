// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {BenqiERC4626Reinvest} from "../BenqiERC4626Reinvest.sol";

import {IBERC20} from "../external/IBERC20.sol";
import {IBComptroller} from "../external/IBComptroller.sol";

contract BenqiERC4626ReinvestTest is Test {
    address public manager;
    address public alice;
    address public bob;

    uint256 public ethFork;
    uint256 public ftmFork;
    uint256 public avaxFork;
    uint256 public polyFork;

    string AVAX_RPC_URL = vm.envString("AVALANCHE_RPC_URL");

    BenqiERC4626Reinvest public vault;
    ERC20 public asset;
    ERC20 public reward;
    IBERC20 public cToken;
    IBComptroller public comptroller;

    uint8 rewardType_;
    address swapToken;
    address pair1;
    address pair2;

    function setUp() public {
        avaxFork = vm.createFork(AVAX_RPC_URL, 19_963_848);
        vm.selectFork(avaxFork);

        manager = msg.sender;
        comptroller = IBComptroller(vm.envAddress("BENQI_COMPTROLLER"));

        setVault(ERC20(vm.envAddress("BENQI_DAI_ASSET")), IBERC20(vm.envAddress("BENQI_DAI_CTOKEN")), comptroller);

        asset = ERC20(vm.envAddress("BENQI_DAI_ASSET"));
        reward = ERC20(vm.envAddress("BENQI_REWARD_QI"));
        cToken = IBERC20(vm.envAddress("BENQI_DAI_CTOKEN"));

        rewardType_ = 0;
        swapToken = vm.envAddress("BENQI_SWAPTOKEN_DAI");
        pair1 = vm.envAddress("BENQI_PAIR1_DAI");
        pair2 = vm.envAddress("BENQI_PAIR2_DAI");

        vm.prank(manager);
        vault.setRoute(rewardType_, address(reward), swapToken, pair1, pair2);

        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 100_000_000 ether);
        deal(address(asset), bob, 100_000_000 ether);

        /// @dev Making contracts persistent
        vm.makePersistent(address(comptroller));
        vm.makePersistent(address(asset));
        vm.makePersistent(address(reward));
        vm.makePersistent(address(cToken));
        vm.makePersistent(alice);
        vm.makePersistent(bob);
    }

    function setVault(ERC20 underylyingAsset, IBERC20 cToken_, IBComptroller comptroller_) public {
        vm.startPrank(manager);

        asset = underylyingAsset;
        reward = reward;
        cToken = cToken_;

        vault = new BenqiERC4626Reinvest(
            underylyingAsset,
            cToken_,
            comptroller_,
            manager
        );

        vm.makePersistent(address(vault));
        vm.makePersistent(address(asset));
        vm.makePersistent(address(reward));
        vm.makePersistent(address(cToken));

        vm.stopPrank();
    }

    function testDepositWithdraw() public {
        uint256 amount = 1_000_000 ether;

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

    /// @dev Contracts require a careful selection of blocks to roll
    function testHarvest() public {
        uint256 amount = 10_000 ether;

        //////////////////////////////////////////////////////////////

        vm.startPrank(alice);
        uint256 aliceUnderlyingAmount = amount;
        asset.approve(address(vault), aliceUnderlyingAmount);
        vault.deposit(aliceUnderlyingAmount, alice);

        console.log("--------FIRST ROLL FORK--------");
        vm.rollFork(26_458_292);

        uint256 rewardsAccrued = vault.getRewardsAccrued(0);
        console.log(block.timestamp, block.number);
        console.log("rewardsAccrued", rewardsAccrued);
        console.log("totalAssets", vault.totalAssets());

        (uint224 index, uint32 timestamp) = comptroller.rewardSupplyState(0, address(cToken));
        console.log("index", index);
        console.log("timestamp", timestamp);

        vm.stopPrank();

        //////////////////////////////////////////////////////////////

        /// @dev Next deposit
        vm.startPrank(bob);
        uint256 bobUnderlyingAmount = amount;
        asset.approve(address(vault), bobUnderlyingAmount);
        vault.deposit(bobUnderlyingAmount, bob);

        console.log("--------SECOND ROLL FORK--------");
        vm.rollFork(26_460_292);

        console.log("totalAssets", vault.totalAssets());
        vm.stopPrank();

        ///////////////////////////////////////////////////////////////

        /// @dev Next deposit
        vm.startPrank(alice);
        asset.approve(address(vault), aliceUnderlyingAmount);
        vault.deposit(aliceUnderlyingAmount, alice);

        rewardsAccrued = vault.getRewardsAccrued(0);
        console.log(block.timestamp, block.number);
        console.log("rewardsAccrued", rewardsAccrued);
        (index, timestamp) = comptroller.rewardSupplyState(0, address(cToken));
        console.log("index", index);
        console.log("timestamp", timestamp);

        console.log("--------HARVEST CALL--------");
        vm.rollFork(26_461_292);

        rewardsAccrued = vault.getRewardsAccrued(0);
        (index, timestamp) = comptroller.rewardSupplyState(0, address(cToken));
        console.log("index", index);
        console.log("timestamp", timestamp);
        console.log("rewardsAccruedPost", rewardsAccrued);
        console.log(block.timestamp, block.number);

        uint256 totalAssetsBeforeHarvest = vault.totalAssets();
        vault.harvest(0, 0);
        uint256 totalAssetsAfterHarvest = vault.totalAssets();
        uint256 rewardsBalanceAfterHarvest = vault.getRewardsAccrued(0);

        assertGt(totalAssetsAfterHarvest, totalAssetsBeforeHarvest);
        assertEq(rewardsBalanceAfterHarvest, 0);
    }
}
