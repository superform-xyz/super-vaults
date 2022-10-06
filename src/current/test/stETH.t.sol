// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {StETHERC4626} from "../eth-staking/stETH.sol";

interface IStETH {
    function getTotalShares() external view returns (uint256);
    function submit(address) external payable returns (uint256);
    function burnShares(address,uint256) external returns (uint256);
    function approve(address,uint256) external returns (bool);
}

interface wstETH {
    function wrap(uint256) external returns (uint256);
    function unwrap(uint256) external returns (uint256);
    function getStETHByWstETH(uint256) external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
}

interface IWETH {
    function wrap(uint256) external payable returns (uint256);
    function unwrap(uint256) external returns (uint256);
}


contract stEthTest is Test {
    uint256 public ethFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    StETHERC4626 public vault;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    IStETH public stEth = IStETH(0xc00e94Cb662C3520282E6f5717214004A7f26888);
    wstETH public wstEth = wstETH(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);
        vault = new StETHERC4626(weth, stEth, wstEth);
    }

    function testDepositWithdraw() public {}

    function testMintRedeem() public {}
}
