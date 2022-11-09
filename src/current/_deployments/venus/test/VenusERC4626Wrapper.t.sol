// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {VenusERC4626Wrapper} from "../VenusERC4626Wrapper.sol";

import {ICERC20} from "../compound/ICERC20.sol";
import {LibCompound} from "../compound/LibCompound.sol";
import {IComptroller} from "../compound/IComptroller.sol";

contract VenusERC4626WrapperTest is Test {
    uint256 public fork;

    string BSC_RPC_URL = vm.envString("BSC_MAINNET_RPC");

    VenusERC4626Wrapper public vault;

    address public manager;
    address public alice;

    /// Change those to .env vars
    ERC20 public usdc = ERC20(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d);
    ERC20 public reward = ERC20(0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63);
    ICERC20 public cToken = ICERC20(0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8);
    IComptroller public comptroller =
        IComptroller(0xf6C14D4DFE45C132822Ce28c646753C54994E59C);

    function setUp() public {
        fork = vm.createFork(BSC_RPC_URL);
        vm.selectFork(fork);

        manager = msg.sender;
        vault = new VenusERC4626Wrapper(
            usdc,
            reward,
            cToken,
            comptroller,
            manager
        );

        alice = address(0x1);
        deal(address(usdc), alice, 1000 ether);
        
        // https://pancakeswap.finance/info/pools/0x7eb5d86fd78f3852a3e0e064f2842d45a3db6ea2
        /// HERE: XVS IS ONLY SWAPPABLE TO WBNB
        /// TWO SWAPS ARE ALWAYS NEEDED XVS>WBNB POOL > WBNB >asset POOL
        address WBNB = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c); // WBNB
        address PAIR1 = address(0x7EB5D86FD78f3852a3e0e064f2842d45a3dB6EA2); // XVS/WBNB
        address PAIR2 = address(0xd99c7F6C65857AC913a8f880A4cb84032AB2FC5b); // WBNB/USDC
        
        vm.prank(manager);
        vault.setRoute(
            WBNB, PAIR1, PAIR2
        );

    }

    function testDepositWithdraw() public {
        uint256 amount = 100 ether;

        /// deal(here)
        vm.startPrank(alice);

        uint256 aliceUnderlyingAmount = amount;

        usdc.approve(address(vault), aliceUnderlyingAmount);
        assertEq(usdc.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 alicePreDepositBal = usdc.balanceOf(alice);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        uint256 aliceAssetsToWithdraw = vault.convertToAssets(aliceShareAmount);
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);

        vault.withdraw(aliceAssetsToWithdraw, alice, alice);
    }

    function testHarvest() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);

        uint256 aliceUnderlyingAmount = amount;

        usdc.approve(address(vault), aliceUnderlyingAmount);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        console.log("totalAssets before harvest", vault.totalAssets());

        deal(address(reward), address(vault), 1000 ether);
        assertEq(reward.balanceOf(address(vault)), 1000 ether);
        vault.harvest();
        assertEq(reward.balanceOf(address(vault)), 0);
        console.log("totalAssets after harvest", vault.totalAssets());
    }
}
