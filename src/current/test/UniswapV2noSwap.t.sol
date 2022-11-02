// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapV2WrapperERC4626Swap} from "../double-sided/swap-built-in/UniswapV2token0.sol";

/// @dev Add testing for other Vault
// import {UniswapV2WrapperERC4626Swap} from "../double-sided/swap-built-in/UniswapV2token1.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../double-sided/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../double-sided/interfaces/IUniswapV2Router.sol";

contract UniswapV2TestSwap is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;
    uint256 public immutable ONE_E18 = 1 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    UniswapV2WrapperERC4626Swap public vault;

    string name = "UniV2ERC4626WrapperSwapper";
    string symbol = "UFC4626";
    ERC20 public dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IUniswapV2Pair public pair =
        IUniswapV2Pair(0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5);
    IUniswapV2Router public router =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public alice;
    address public manager;

    uint256 public slippage = 30; /// 0.3

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new UniswapV2WrapperERC4626Swap(
            name,
            symbol,
            dai,
            router,
            pair,
            slippage
        );
        alice = address(0x1);
        manager = msg.sender;

        deal(address(dai), alice, ONE_THOUSAND_E18 * 2);
        deal(address(usdc), alice, 1000e6 * 2);
    }

    function testDepositWithdraw0() public {
        uint256 amount = 100 ether;

        vm.startPrank(alice);

        dai.approve(address(vault), amount);

        uint256 aliceShareAmount = vault.deposit(amount, alice);

        /// TODO fix!
        // vault.withdraw(aliceShareAmount, alice, alice);
    }

}
