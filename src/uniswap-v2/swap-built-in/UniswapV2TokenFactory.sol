// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";
import {UniswapV2Library} from "../utils/UniswapV2Library.sol";

import {DexSwap} from "../utils/swapUtils.sol";
import {UniswapV2WrapperERC4626Swap} from "./UniswapV2token0.sol";

import "forge-std/console.sol";

contract UniswapV2TokenFactory {

    constructor() {}

    function create(IUniswapV2Pair pair) external {

    }
}