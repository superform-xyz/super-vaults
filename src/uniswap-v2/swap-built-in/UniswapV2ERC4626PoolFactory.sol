// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";
import {UniswapV2ERC4626Swap} from "./UniswapV2ERC4626Swap.sol";

import {IUniswapV3Factory} from "../interfaces/IUniswapV3.sol";
import {IUniswapV3Pool} from "../interfaces/IUniswapV3.sol";

/// @title WIP: Uniswap V2 ERC4626 Pool Factory for instant deployment of adapter for two tokens of the Pair.
/// @notice Use for stress-free deployment of an adapter for a single uniswap V2 pair. Oracle functionality is currently disabled.
contract UniswapV2ERC4626PoolFactory {
    IUniswapV2Router router;
    IUniswapV3Factory oracleFactory;

    constructor(IUniswapV2Router router_, IUniswapV3Factory oracleFactory_) {
        router = router_;
        oracleFactory = oracleFactory_;
    }

    function create(IUniswapV2Pair pair, uint24 fee)
        external
        returns (UniswapV2ERC4626Swap v0, UniswapV2ERC4626Swap v1, address oracle)
    {
        /// @dev Tokens sorted by uniswapV2pair
        ERC20 token0 = ERC20(pair.token0());
        ERC20 token1 = ERC20(pair.token1());

        /// @dev Each UniV3 Pool is a twap oracle
        require((oracle = twap(address(token0), address(token1), fee)) != address(0), "twap doesn't exist");
        
        IUniswapV3Pool oracle_ = IUniswapV3Pool(oracle);

        /// @dev For uniswap V2 only two tokens pool
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

        /// @dev For uniswap V2 only two tokens pool
        v0 = new UniswapV2ERC4626Swap(
            token0,
            name0,
            symbol0,
            router,
            pair,
            oracle_
        );

        v1 = new UniswapV2ERC4626Swap(
            token1,
            name1,
            symbol1,
            router,
            pair,
            oracle_
        );
    }

    function twap(address token0, address token1, uint24 fee) public view returns (address) {
        return oracleFactory.getPool(token0, token1, fee);
    }

}
