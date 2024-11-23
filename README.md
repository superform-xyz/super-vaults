# Super-vaults

Repository contains different types of ERC4626 adapters/wrappers for non-standardized DeFi Vaults. We follow [yield-daddy](https://github.com/timeless-fi/yield-daddy) implementation for some of the AAVE & Compound forked protocols, adding reward harvesting, but we also provide a set of original adapters over protocols like Arrakis, Lido, Uniswap or Compound-V3. 

A goal of this repository is to build a useful reference codebase to follow when implementing ERC4626 compatible adapters and vaults.

You can find individual `README.md` files in some of the protocol directories inside of `/src` expanding on adapter implementation. Some of the adapters are still considered experimental and/or not fully tested. 

### Disclaimer

Super-vaults is still work in progress. A lot of code has highly experimental nature and shouldn't be trusted in mainnet usage.

# Build

Repository uses MakeFile to streamline testing operations. 

Create `.env` file with RPC_URLs, otherwise tests will fail!

Copy contents of `constants.env` to your local `.env` file (Tests are run against forked state, we read target addresses from env)

`make install`

`make build`

`make test`

You can match individual test files with:

`make test-aave` for testing aave

`make test-compound` for testing compound

`make test-steth` for testing lido's stEth

_(see MakeFile for more examples)_

# Slither

To run Slither over the specific file. 

`slither src/<PROTOCOL-DIR>/<NAME-OF-THE-VAULT>.sol --config-file slither.config.json`

# Structure

Each protocol is hosted inside of a separate directory. For a single protocol we expect to see many different types of ERC4626 Vaults and Wrappers/Adapters. Starting from the most basic, allowing only zapIn/zapOut to the non-ERC4626 Vault through the ERC4626 interface ending on "unique" ERC4626 implementations. If you plan on adding your own wrapper or standalone ERC4626 Vault, create a PR following existing root directory structure: 

General view:

    .
    ├── src
      ├── aave-v2
      ├── aave-v3
      ├── alpaca
      ├── arrakis
      ├── benqi
      ├── compound
      ├── geist
      ├── kycdao-4626      
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

Each protocol directory should have its own `test` with corresponding entry in `MakeFile`. Follow established naming patterns. You can create additional directories inside of a protocol directory or host your Vaults together in root directory.
