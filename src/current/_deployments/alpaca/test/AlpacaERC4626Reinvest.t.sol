// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {AlpacaERC4626Reinvest} from "../AlpacaERC4626Reinvest.sol";

import {IBToken} from "../interfaces/IBToken.sol";
import {IFairLaunch} from "../interfaces/IFairLaunch.sol";

contract AlpacaERC4626ReinvestTest is Test {
    uint256 public bscFork;
    address public manager;

    string BSC_RPC_URL = vm.envString("BSC_MAINNET_RPC");

    AlpacaERC4626Reinvest public vault;

    IBToken public token = IBToken(vm.envAddress("ALPACA"));
    IFairLaunch public fairLaunch = IFairLaunch(vm.envAddress("FAIR_LAUNCH"));

    constructor() {
        bscFork = vm.createFork(BSC_RPC_URL);
        vm.selectFork(bscFork);
        manager = msg.sender;

        setVault(IBToken(vm.envAddress("ALPACA")), vm.envUint("POOL_ID"));
    }

    function setVault(IBToken token_, uint256 poolId_) public {
        vm.startPrank(manager);

        token = token_;

        vault = new AlpacaERC4626Reinvest(token, fairLaunch, poolId_);

        vm.stopPrank();
    }
}
