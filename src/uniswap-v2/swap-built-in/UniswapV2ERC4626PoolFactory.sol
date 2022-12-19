// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";
import {UniswapV2ERC4626Swap} from "./UniswapV2ERC4626Swap.sol";

contract UniswapV2ERC4626PoolFactory {
    IUniswapV2Router router;

    constructor(IUniswapV2Router router_) {
        router = router_;
    }

    function create(IUniswapV2Pair pair)
        external
        returns (UniswapV2ERC4626Swap v0, UniswapV2ERC4626Swap v1)
    {
        /// TODO: invariant dependant, only temp here
        uint256 slippage = 30; /// 0.3

        /// @dev Tokens sorted by uniswapV2pair
        ERC20 token0 = ERC20(pair.token0());
        ERC20 token1 = ERC20(pair.token1());

        /// @dev For uniswap V2 there're always only two tokens
        /// @dev using symbol for naming to keep it short
        string memory name0 = string(
            abi.encodePacked("UniV2-", token0.symbol(), "-ERC4626")
        );
        string memory name1 = string(
            abi.encodePacked("UniV2-", token1.symbol(), "-ERC4626")
        );
        string memory symbol0 = string(
            abi.encodePacked("UniV2-", token0.symbol())
        );
        string memory symbol1 = string(
            abi.encodePacked("UniV2-", token1.symbol())
        );

        /// @dev For uniswap V2 there're always only two tokens
        v0 = new UniswapV2ERC4626Swap(
            token0,
            name0,
            symbol0,
            router,
            pair,
            slippage
        );

        v1 = new UniswapV2ERC4626Swap(
            token1,
            name1,
            symbol1,
            router,
            pair,
            slippage
        );
    }
}
