# Super-vaults

ERC4626 Wrappers/Adapters for SuperForm's multichain Vault system.

Main extension over standard ERC4626 is `harvest()` capability, exchanging and reinvesting rewards distributed to the Vault adapter in form of its underlying token. In-development feature is ERC4626 adapter over UniswapV2 Pair, providing built-in capability of flexible join/exit into UniswapV2 type pools from single or double token transfers handled by ERC4626 interface. Repository utilizes [yield-daddy](https://github.com/timeless-fi/yield-daddy) set of ERC4626 wrappers for its base.

Early release, a lot of code is not deployment ready!

# Build

Repository uses MakeFile to streamline testing operations. 

Create `.env` file with RPC_URLs, otherwise tests will fail!

`make install`

`make build`

`make test`

You can match individual test files with:

`make test-aave` for testing aave

`make test-compound` for testing compound

`make test-steth` for testing lido's stEth

_(see MakeFile)_

# Slither

To run Slither over the specific file: 

`slither src/uniswap-v2/swap-built-in/UniswapV2ERC4626Swap.sol --config-file slither.config.json`

# Structure

Each protocol is hosted inside of a separate directory. For a single protocol we expect to see many different types of ERC4626 Vaults and Wrappers/Adapters. Starting from the most basic, allowing only zapIn/zapOut to the non-ERC4626 Vault through the ERC4626 interface ending on complex yield applications. If you plan on adding your own wrapper or standalone ERC4626 Vault, create a PR following existing root directory structure, like: 

General view:

    .
    ├── src
      ├── aave-v2
      ├── aave-v3
      ├── alpaca
      ├── arrakis
      ├── benqi
      ├── compound-v2
      ├── lido
      ├── rocketPool
      ├── uniswap-v2
      ├── venus

Detailed view, inside of a protocol directory:

    .
    ├── protocol-name
      ├── interface
      ├── test
          ├── ExampleERC4626Vault.t.sol
          ├── otherERC4626Vault.t.sol
      ├── other-implementation-1
      ├── next-implementation-2
      ├── ExampleERC4626Vault.sol

Each protocol directory should have its own `test` with coresponding entry in `MakeFile`. Follow established naming patterns. You can create additional directories inside of a protocol directory or host your Vaults together in root directory.