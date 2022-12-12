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
import {UniswapV2ERC4626Swap} from "./UniswapV2ERC4626Swap.sol";

import "forge-std/console.sol";

contract UniswapV2ERC4626PoolFactory {
    IUniswapV2Router router;

    constructor() {}

    function create(IUniswapV2Pair pair) external {
        uint256 slippage = 30; /// 0.3

        ERC20[] memory tokens = new ERC20[](2);

        ERC20 token0 = ERC20(pair.token0());
        ERC20 token1 = ERC20(pair.token1());

        tokens[0] = token0;
        tokens[1] = token1;

        for (uint256 i = 0; i < tokens.length; i++) {
            string memory name = string(
                abi.encodePacked("UniV2-", tokens[i].name(), "-ERC4626")
            );
            string memory symbol = string(
                abi.encodePacked("UniLP-", tokens[i].symbol())
            );

            UniswapV2ERC4626Swap vault = new UniswapV2ERC4626Swap(
                tokens[i],
                name,
                symbol,
                router,
                pair,
                slippage
            );
        }
    }
}
