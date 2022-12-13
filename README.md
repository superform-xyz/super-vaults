# Super-vaults

ERC4626 Wrappers/Adapters for SuperForm's multichain Vault system. 

# Build

Repository uses MakeFile to streamline testing operations. 

Create `.env` file with RPC_URLs, otherwise tests will fail!

`make install`

`make build`

`make test`

Or you can `match-contract` individual test files

`make test-aave` for testing aave

`make test-compound` for testing compound

`make test-steth` for testing lido's stEth

(see MakeFile)

# Structure

Each protocol is hosted inside of a separate directory. For a single protocol we expect to see many different types of ERC4626 Vaults and Wrappers/Adapters. Starting from the most basic, allowing only zapIn/zapOut to the non-ERC4626 Vault through the ERC4626 interface, ending on complex yield focused applications. If you plan on adding your own wrapper or standalone ERC4626 Vault, create a PR with the whole directory and follow existing root directory structure, for example

    .
    ├── protocol-name
      ├── interface
      ├── test
      ├── vault-implementation-1
      ├── vault-implementation-2
      ├── ExampleVault.sol