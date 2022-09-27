# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
install:; forge install
update:; forge update

# Build & test
build  :; forge build
test   :; forge test --no-match-contract Alpaca\|Benqi.*Test
test-old :; forge test --match-contract Alpaca\|Benqi.*Test
clean  :; forge clean
snapshot :; forge snapshot
fmt    :; forge fmt && forge fmt test/
# test-mainnet-bnb :; forge test --fork-url $(RPC_URL_MAINNET) --match-contract Alpaca_BTC_Test\|StETHERC4626.*Test -vvv