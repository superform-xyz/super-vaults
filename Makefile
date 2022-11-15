# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env
-include .env.addresses

# deps
install:; forge install
update:; forge update

# Build & test
build  :; forge build
test   :; forge test --no-match-contract rEthTest -vvv # skip rEthTest*.*Test TODO: slot check
clean  :; forge clean
snapshot :; forge snapshot
fmt    :; forge fmt && forge fmt test/

test-aave :; forge test --match-contract AaveV2* -vvv
test-compound :; forge test --match-contract CompoundV2* -vvv
test-steth :; forge test --match-contract stEth.*Test -vvv
test-steth2 :; forge test --match-contract stEthNoSwap.*Test -vvv
test-wmatic :; forge test --match-contract stMatic.*Test -vvv
test-uniswapV2 :; forge test --match-contract UniswapV2Test -vvv
test-uniswapV2swap :; forge test --match-contract UniswapV2TestSwap -vvv
test-reth :; forge test --match-contract rEthTest -vvv
test-arrakis :; forge test --match-contract Arrakis_LP_Test -vvv

# Reinvest test
test-venus :; forge test --match-contract VenusERC4626WrapperTest -vvv
test-aaveV2-reinvest :; forge test --match-contract AaveV2ERC4626ReinvestTest -vvv
test-aaveV3-reinvest :; forge test --match-contract AaveV3ERC4626ReinvestTest -vvv
test-benqi-reinvest :; forge test --match-contract BenqiERC4626ReinvestTest -vvv

### BINANCE CHAIN

# USDC/vUSDC/XVS/Comptroller
deploy-venus-usdc :; forge create --rpc-url $(BSC_MAINNET_RPC) \
				--constructor-args $(VENUS_USDC_ASSET) $(VENUS_REWARD_XVS) $(VENUS_VUSDC_CTOKEN) $(VENUS_COMPTROLLER) $(MANAGER) \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

deploy-venus-dai :; forge create --rpc-url $(BSC_MAINNET_RPC) \
				--constructor-args $(ASSET) $(REWARD) $(CTOKEN) $(COMPTROLLER) $(MANAGER) \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

# Already deployed (check status)
deploy-alpaca :; forge create --rpc-url $(BSC_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

# USDC/WBNB https://pancakeswap.finance/info/pools/0x16b9a82891338f9ba80e2d6970fdda79d1eb0dae
deploy-pancakeswap :; forge create --rpc-url $(BSC_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

### POLYGON

# MATIC/DAI/USDC SUPPLY (ERC20)
deploy-aave2-poly :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

# MATIC/DAI/USDC SUPPLY (ERC20)
deploy-aave3-poly :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

# WMATIC/USDC (ERC20)
deploy-arrakis-poly :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

# WMATIC/USDC (ERC20) https://quickswap.exchange/#/analytics/v2/pair/0x6e7a5fafcec6bb1e78bae2a1f0b612012bf14827
deploy-quickswap-poly :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

### AVAX

# AVAX (NATIVE) / DAI.e (ERC20) / USDC.e (ERC20) - gives WAVAX rewards
deploy-aave3-avax :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

# AVAX (NATIVE) / DAI.e (ERC20) / USDC.e (ERC20) - no WAVAX rewards
deploy-aave2-avax :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

# AVAX (NATIVE) / DAI.e (ERC20) / USDC.e (ERC20) - claim QI rewards https://app.benqi.fi/markets
deploy-benqi-avax :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify


deploy-traderjoe-avax :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

### ARBITRUM

# DAI (ERC20) / USDC (ERC20)
deploy-aave3-arbitrum :; forge create --rpc-url $(ARBITRUM_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

deploy-sushi-arbitrum :; forge create --rpc-url $(ARBITRUM_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

### OPTIMISM

# DAI (ERC20) / USDC (ERC20)
deploy-aave3-optimism :; forge create --rpc-url $(OPTIMISM_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify

### FANTOM
deploy-spookyswap-fantom :; forge create --rpc-url $(FTM_MAINNET_RPC) \
				--constructor-args "" "" 18 1000 \ 
				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester \
				--etherscan-api-key $(ETHERSCAN_API_KEY) \
				--verify