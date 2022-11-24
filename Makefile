# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env
-include .addresses

# deps
install:; forge install
update:; forge update

# Build & test
build  :; forge build
test   :; forge test --no-match-contract rEthTest\|stEthSwapTest -vvv # skip rEthTest*.*Test TODO: slot check
clean  :; forge clean
snapshot :; forge snapshot
fmt    :; forge fmt && forge fmt test/

# General test
test-aave :; forge test --match-contract Aave* -vvv
test-compound :; forge test --match-contract CompoundV2* -vvv
test-steth :; forge test --match-contract stEth.*Test -vvv
# test-steth-swap :; forge test --match-contract stEthSwap.*Test -vvv # fix & extend
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
test-benqiNative-reinvest :; forge test --match-contract BenqiNativeERC4626ReinvestTest -vvv

# Harvester tests (check tests comments)
test-aaveV3-harvest :; forge test --match-contract AaveV3ERC4626ReinvestTest --match-test testHarvester -vvv

####################
### BINANCE CHAIN ##
####################

# USDC/vUSDC/XVS/Comptroller
# deploy-venus-usdc :; forge create --rpc-url $(BSC_MAINNET_RPC) \
# 				--constructor-args $(VENUS_USDC_ASSET) $(VENUS_REWARD_XVS) $(VENUS_VUSDC_CTOKEN) $(VENUS_COMPTROLLER) $(MANAGER) \ 
# 				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester


# deploy-venus-dai :; forge create --rpc-url $(BSC_MAINNET_RPC) \
# 				--constructor-args $(ASSET) $(REWARD) $(CTOKEN) $(COMPTROLLER) $(MANAGER) \ 
# 				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester


# Already deployed (check status)
#deploy-alpaca :; forge create --rpc-url $(BSC_MAINNET_RPC) \
#				--constructor-args "" "" 18 1000 \ 
#				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester


# USDC/WBNB https://pancakeswap.finance/info/pools/0x16b9a82891338f9ba80e2d6970fdda79d1eb0dae
#deploy-pancakeswap :; forge create --rpc-url $(BSC_MAINNET_RPC) \
#				--constructor-args "" "" 18 1000 \ 
#				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester


##############
### POLYGON ##
##############

# AAVE-V3-POLY-USDC
deploy-aave3-polygon-dai :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
				--constructor-args $(AAVEV3_POLYGON_DAI) $(AAVEV3_POLYGON_ADAI) $(AAVEV3_POLYGON_LENDINGPOOL) $(AAVEV3_POLYGON_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V3-POLY-DAI
deploy-aave3-polygon-usdc :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
				--constructor-args $(AAVEV3_POLYGON_USDC) $(AAVEV3_POLYGON_AUSDC) $(AAVEV3_POLYGON_LENDINGPOOL) $(AAVEV3_POLYGON_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V2-POLY-DAI
deploy-aave2-polygon-dai :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
				--constructor-args $(AAVEV2_POLYGON_DAI) $(AAVEV2_POLYGON_ADAI) $(AAVEV2_POLYGON_REWARDS) $(AAVEV2_POLYGON_LENDINGPOOL) $(AAVEV2_POLYGON_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626Reinvest.sol:AaveV2ERC4626Reinvest

# AAVE-V2-POLY-WMATIC
deploy-aave2-polygon-wmatic :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
				--constructor-args $(AAVEV2_POLYGON_WMATIC) $(AAVEV2_POLYGON_AWMATIC) $(AAVEV2_POLYGON_REWARDS) $(AAVEV2_POLYGON_LENDINGPOOL) $(AAVEV2_POLYGON_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626Reinvest.sol:AaveV2ERC4626Reinvest

# WMATIC/USDC (ERC20)
# deploy-arrakis-poly :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
# 				--constructor-args "" "" 18 1000 \ 
# 				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester
 

# WMATIC/USDC (ERC20) https://quickswap.exchange/#/analytics/v2/pair/0x6e7a5fafcec6bb1e78bae2a1f0b612012bf14827
# deploy-quickswap-poly :; forge create --rpc-url $(POLYGON_MAINNET_RPC) \
# 				--constructor-args "" "" 18 1000 \ 
# 				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester


#############
### AVAX ####
#############

# AAVE-V3-AVAX-USDC
deploy-aave3-avax-usdc :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
				--constructor-args $(AAVEV3_AVAX_USDC) $(AAVEV3_AVAX_AUSDC) $(AAVEV3_AVAX_LENDINGPOOL) $(AAVEV3_AVAX_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V3-AVAX-DAI
deploy-aave3-avax-dai :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
				--constructor-args $(AAVEV3_AVAX_DAI) $(AAVEV3_AVAX_ADAI) $(AAVEV3_AVAX_LENDINGPOOL) $(AAVEV3_AVAX_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V2-AVAX-DAI
deploy-aave2-avax-dai :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
				--constructor-args $(AAVEV2_AVAX_DAI) $(AAVEV2_AVAX_ADAI) $(AAVEV2_AVAX_REWARDS) $(AAVEV2_AVAX_LENDINGPOOL) $(AAVEV2_AVAX_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626Reinvest.sol:AaveV2ERC4626Reinvest

# AAVE-V2-AVAX-WAVAX
deploy-aave2-avax-wavax :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
				--constructor-args $(AAVEV2_AVAX_WAVAX) $(AAVEV2_AVAX_AWAVAX) $(AAVEV2_AVAX_REWARDS) $(AAVEV2_AVAX_LENDINGPOOL) $(AAVEV2_AVAX_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626Reinvest.sol:AaveV2ERC4626Reinvest

# AVAX (NATIVE) / DAI.e (ERC20) / USDC.e (ERC20) - claim QI rewards https://app.benqi.fi/markets
# deploy-benqi-avax :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
# 				--constructor-args "" "" 18 1000 \ 
# 				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester



# deploy-traderjoe-avax :; forge create --rpc-url $(AVAX_MAINNET_RPC) \
# 				--constructor-args "" "" 18 1000 \ 
# 				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester


###############
### ARBITRUM ##
###############

# AAVE-V3-ARB-DAI
deploy-aave3-arbitrum-dai :; forge create --rpc-url $(ARBITRUM_MAINNET_RPC) \
				--constructor-args $(AAVEV3_ARBITRUM_DAI) $(AAVEV3_ARBITRUM_ADAI) $(AAVEV3_ARBITRUM_LENDINGPOOL) $(AAVEV3_ARBITRUM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V3-ARB-USDC
deploy-aave3-arbitrum-usdc :; forge create --rpc-url $(ARBITRUM_MAINNET_RPC) \
				--constructor-args $(AAVEV3_ARBITRUM_USDC) $(AAVEV3_ARBITRUM_AUSDC) $(AAVEV3_ARBITRUM_LENDINGPOOL) $(AAVEV3_ARBITRUM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest


# deploy-sushi-arbitrum :; forge create --rpc-url $(ARBITRUM_MAINNET_RPC) \
# 				--constructor-args "" "" 18 1000 \ 
# 				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester


###############
### OPTIMISM ##
###############

# AAVE-V3-OPT-DAI
deploy-aave3-optimism-dai :; forge create --rpc-url $(OPTIMISM_MAINNET_RPC) \
				--constructor-args $(AAVEV3_OPTIMISM_DAI) $(AAVEV3_OPTIMISM_ADAI) $(AAVEV3_OPTIMISM_LENDINGPOOL) $(AAVEV3_OPTIMISM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V3-OPT-USDC
deploy-aave3-optimism-usdc :; forge create --rpc-url $(OPTIMISM_MAINNET_RPC) \
				--constructor-args $(AAVEV3_OPTIMISM_USDC) $(AAVEV3_OPTIMISM_AUSDC) $(AAVEV3_OPTIMISM_LENDINGPOOL) $(AAVEV3_OPTIMISM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

###############
### FANTOM ####
###############

# deploy-spookyswap-fantom :; forge create --rpc-url $(FTM_MAINNET_RPC) \
# 				--constructor-args "" "" 18 1000 \ 
# 				--private-key $(PRIVATE_KEY) src/current/aave-v2/AaveV2StrategyWrapperNoHarvester:AaveV2StrategyWrapperNoHarvester
