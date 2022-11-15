# Super-vaults

ERC4626 Wrappers for SuperForm's Vault system. 

# Build

Repository uses MakeFile to streamline testing operations. You can use `forge install` and other forge naitive commands, but expected execution is achived with `make`.

Create `.env` file with RPC_URLs, otherwise tests will fail!

`make install`

`make build`

`make test`

Or you can `match-contract` 

`make test-aave` for testing aave

`make test-compound` for testing compound

`make test-steth` for testing lido's stEth

... (check the Makefile for more)

# Structure

Each protocol resides inside of a separate directory. For a single protocol we expect to see many different wrappers. Starting from the most basic, allowing only zapIn/zapOut of the non-ERC4626 Vault through the ERC4626 interface, ending on the reinvesting strategies or levaraged position management. If you plan on adding your own wrapper or standalone ERC4626 Vault, PR with the whole directory following established structure.

# Disclaimer

This is still work in progress. There are on-going standarization efforts for this repository with an end goal of providing all the neccessary toolkit and templates for working with ERC4626.