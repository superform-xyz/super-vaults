# Super-vaults

ERC4626 different wrappers for SuperForm Vault system

# Build

`forge build`

# To run OLD test:

You need to run specific tests with correct RPC endpoint for given network, global command `forge test` won't successfully execute tests.

_for BNB Vaults_

Command: `forge test -f https://bsc-dataseed.binance.org/ --match-contract Alpaca_BTC_Test` ( for matching bnb chain contracts)

_for Avalanche Vaults_:

command: `forge test -f https://api.avax.network/ext/bc/C/rpc --match-contract BenqiUSDCTest --match-test testWithdrawSuccess -vv` ( -vv increases verbosity)