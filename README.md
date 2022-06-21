# super-vaults
Super vaults wrapping yield opportunities on every chain

# Build
forge build
# To run test:
for BNB Vaults

Command: forge test -f https://bsc-dataseed.binance.org/ --match-contract Alpaca_BTC_Test ( for matching bnb chain contracts)

for Avalanche Vaults:

command: forge test -f https://api.avax.network/ext/bc/C/rpc --match-contract BenqiUSDCTest --match-test testWithdrawSuccess -vv (vv gives the logs, vvv and vvvv to increase verbosity)

# Developers Space
Alpaca vault itself acts as rewardClaimer for harvesting staking yield.

Benqi vault contains a rewardsCore which acts as an abstract for rewardClaiming logic, can extend it to use it for the re-invest too., WIP()