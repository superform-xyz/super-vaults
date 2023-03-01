# Uniswap V2 Pool ERC4626 Adapters

`./swap-built-in/UniswapV2ERC4626Swap.sol`

Enables users to deposit into Uniswap V2 Pools using either token0 or token1 and receive an Uniswap LP-token representation wrapped in ERC4626 interface. The Vault calculates the optimal amount for splitting the input token into the two required tokens for the deposit operation. When withdrawing, the Vault simulates the expected value of either token0 or token1 (depending on the Vault being used) within a block. The Vault then performs swapJoin() and swapExit() operations to swap the appropriate amounts of token0 and token1 required for the withdrawal. This system can be easily deployed for token0 and token1 of the UniswapV2Pair, using the UniswapV2ERC4626PoolFactory.sol. Currently `UniswapV2ERC4626PoolFactory.sol` is unfinished and therefore on-chain oracle functionality is disabled. Enabling of Factory contract will be paired with neccessary security updates to the core UniswapV2 adapter.

`./no-swap/UniswapV2.sol`

Allows users to deposit into Uniswap V2 Pools by "yanking" both token0 and token1 from their addresses in exchange for an Uniswap LP-token representation wrapped in ERC4626 interface. Uniswap Pair LP-Token is used for internal accounting, and users are expected to transfer token0 and token1 calculated before the call amounts to a Vault address in exchange for a predetermined amount of Pair token. In contrast to `UniswapV2ERC4626Swap.sol` this implementation can be understood as less automated.

# Risks (WIP)

It is important for users to exercise caution when integrating with this contract, as UniswapV2Pair reserves can be easily manipulated for a single block. This manipulation, however, can only lead to a smaller output amount of shares and will not result in any loss of funds across the vault or other accounting errors. This is because the UniswapV2ERC4626Swap adapter operates on a 1:1 basis with the LP-Token of Uniswap. Therefore, getting more or less of the LP-Token is only relevant to the caller and will not affect the shares <> assets calculation.

# TODO

TODO: Price manipulation protection