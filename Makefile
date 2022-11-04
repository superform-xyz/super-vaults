# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
install:; forge install
update:; forge update

# Build & test
build  :; forge build
test   :; forge test --no-match-contract rEthTest\|Alpaca\|Benqi*.*Test -vv
test-old :; forge test --match-contract Alpaca\|Benqi.*Test
clean  :; forge clean
snapshot :; forge snapshot
fmt    :; forge fmt && forge fmt test/
test-aave :; forge test --fork-url $(FTM_MAINNET_RPC) --match-contract AaveV2* -vvv
test-compound :; forge test --match-contract CompoundV2StrategyWrapperTest -vvv
test-steth :; forge test --match-contract stEth.*Test -vvv
test-steth2 :; forge test --match-contract stEthNoSwap.*Test -vvv
test-wmatic :; forge test --match-contract stMatic.*Test -vvv
test-uniswapV2 :; forge test --match-contract UniswapV2Test -vvv
test-uniswapV2swap :; forge test --match-contract UniswapV2TestSwap -vv
test-reth :; forge test --match-contract rEthTest -vvv