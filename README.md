# Super-vaults

ERC4626 different wrappers for SuperForm Vault system

# Build

Repository uses MakeFile to streamline testing operations. You can use `forge install` and other forge naitive commands, but expected execution is achived with `make`.

`make install`

`make build`

`make test` for current implementation

`make test-aave` for testing aave (forked FTM)

`make test-compound` for testing compound (forked ETH)

`make test-steth` for testing aave (forked ETH)

`make test-old` for old implementation

# To run OLD test:

You need to run specific tests with correct RPC endpoint for given network, global command `forge test` won't successfully execute tests.

_for BNB Vaults_

Command: `forge test -f https://bsc-dataseed.binance.org/ --match-contract Alpaca_BTC_Test` ( for matching bnb chain contracts)

_for Avalanche Vaults_:

command: `forge test -f https://api.avax.network/ext/bc/C/rpc --match-contract BenqiUSDCTest --match-test testWithdrawSuccess -vv` ( -vv increases verbosity)