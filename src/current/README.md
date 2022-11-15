# Navigation

`arrakis` - wrapper around arrakis vaults for active uni V3 liquidity management

`aave-v2` - aave v2 erc4626 template (only `NoHarvester` version is implemented and used)

`compound-v2` - compound v2 erc46256 template

`double-sided` - erc4626 custom wrapper for two-token pools

    `no-swap` - uniswap v2 wrapper, keeping ERC4626 interface but breaking its logic, user supplies two tokens and there's no single sided liquidity addition

    `swap-built-in` - uniswap v2 wrapper, keeps full ERC4626 interface and logic, works as single sided liquidity supply, performs a swap from underlying asset to two tokens

`token-staking` - lido's stEth/stMatic wrappers and rocketPool's rETH (no free slot calculation for now, will revert)

`test` - directory containing test files for all of the above

`utils` - helpers, mocks, harvester's swap library - in `swapUtils.sol`, ignore `/harvest` (harvester implementation is used in a lot of contracts)
