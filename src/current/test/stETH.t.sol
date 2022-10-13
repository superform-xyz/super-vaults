// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {StETHERC4626} from "../eth-staking/stETH.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {ICurve} from "../eth-staking/interfaces/ICurve.sol";
import {IStETH} from "../eth-staking/interfaces/IStETH.sol";
import {IWETH} from "../eth-staking/interfaces/IWETH.sol";
import {wstETH} from "../eth-staking/interfaces/wstETH.sol";

contract stEthTest is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    StETHERC4626 public vault;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public curvePool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    address public alice;
    address public manager;

    IWETH public _weth = IWETH(weth);
    IStETH public _stEth = IStETH(stEth);
    wstETH public _wstEth = wstETH(wstEth);
    ICurve public _curvePool = ICurve(curvePool);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new StETHERC4626(weth, stEth, wstEth, curvePool);
        alice = address(0x1);
        manager = msg.sender;

        deal(weth, alice, ONE_THOUSAND_E18);
        deal(weth, manager, ONE_THOUSAND_E18);
    }

    function testDepositWithdraw() public {
        uint256 aliceUnderlyingAmount = HUNDRED_E18;

        vm.startPrank(alice);

        _weth.approve(address(vault), aliceUnderlyingAmount);
        assertEq(_weth.allowance(alice, address(vault)), aliceUnderlyingAmount);

        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
        console.log("aliceShareAmount", aliceShareAmount);

        uint256 aliceAssetsFromShares = vault.convertToAssets(aliceShareAmount);
        console.log("aliceAssetsFromShares", aliceAssetsFromShares);

        vault.withdraw(aliceShareAmount, alice, alice);
    }

    function testPureSteth() public {
        vm.startPrank(alice);

        uint256 stEthAmount = _stEth.submit{value: 1 ether}(alice);
        uint256 sharesOfAmt = _stEth.sharesOf(alice);
        uint256 ethFromStEth = _stEth.getPooledEthByShares(sharesOfAmt);
        uint256 balanceOfStEth = _stEth.balanceOf(alice);

        console.log("sharesOfAmt", sharesOfAmt); /// <= This equals SHARES, not amount of stETH (rebasing)
        console.log("ethFromStEth", ethFromStEth); /// <= This is amount of ETH from stETH shares if users would redeem in this block
        console.log("balanceOfStEth", balanceOfStEth); /// <= This is actual number of tokens held (transferable)

        _stEth.approve(wstEth, stEthAmount);
        uint256 wstEthAmount = _wstEth.wrap(stEthAmount);

        console.log("stEthAmount", stEthAmount);
        console.log("wstEthAmount", wstEthAmount);

        stEthAmount = _wstEth.unwrap(wstEthAmount);
        console.log("stEthAmount unwraped", stEthAmount);

        _stEth.approve(address(curvePool), balanceOfStEth);

        uint256 min_dy = (_curvePool.get_dy(1, 0, balanceOfStEth) * 9900) /
            10000; /// 1% slip
        console.log("min dy", min_dy);

        /// 1 = 0xEeE, 0 = stEth
        uint256 amount = _curvePool.exchange(1, 0, balanceOfStEth, min_dy);
        console.log("curve amount", amount);
    }
}
