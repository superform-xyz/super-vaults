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

    string ETH_RPC_URL = vm.envString("ETHEREUM_RPC_URL");
    string FTM_RPC_URL = vm.envString("FANTOM_RPC_URL");
    string AVAX_RPC_URL = vm.envString("AVALANCHE_RPC_URL");
    string POLYGON_RPC_URL = vm.envString("POLYGON_RPC_URL");

    BenqiERC4626Reinvest public vault;
    ERC20 public asset;
    ERC20 public reward;
    ICERC20 public cToken;
    IComptroller public comptroller;

    uint8 rewardType_;
    address swapToken;
    address pair1;
    address pair2;

    constructor() {
        avaxFork = vm.createFork(AVAX_RPC_URL);
        vm.selectFork(avaxFork);
        vm.roll(12649496);
        manager = msg.sender;
        comptroller = IComptroller(vm.envAddress("BENQI_COMPTROLLER"));

        /// Set vault as fallback
        setVault(
            ERC20(vm.envAddress("BENQI_USDC_ASSET")),
            ICERC20(vm.envAddress("BENQI_USDC_CTOKEN")),
            comptroller
        );

        asset = ERC20(vm.envAddress("BENQI_USDC_ASSET"));
        reward = ERC20(vm.envAddress("BENQI_REWARD_QI"));
        cToken = ICERC20(vm.envAddress("BENQI_USDC_CTOKEN"));

        rewardType_ = 0;
        swapToken = vm.envAddress("BENQI_SWAPTOKEN_USDC");
        pair1 = vm.envAddress("BENQI_PAIR1_USDC");
        pair2 = vm.envAddress("BENQI_PAIR2_USDC");
    }

    function setUp() public {
        alice = address(0x1);
        bob = address(0x2);
        deal(address(asset), alice, 100000000 ether);
        deal(address(asset), bob, 100000000 ether);
    }

    function setVault(
        ERC20 underylyingAsset,
        ICERC20 cToken_,
        IComptroller comptroller_
    ) public {
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

        vm.stopPrank();
    }

    function testRewards() public {
        vm.startPrank(manager);
        vault.setRoute(rewardType_, address(reward), swapToken, pair1, pair2);
        /// @dev Transfer 1 QI token
        deal(address(reward), address(vault), 1000000 ether);
        vault.harvest(rewardType_);
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
        // vm.roll(22378835);
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
