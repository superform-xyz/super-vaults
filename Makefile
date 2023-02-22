# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
install:; forge install
update:; forge update

# Build & test
build  :; forge build
test   :; forge test --no-match-contract stEthSwapTest -vvv
clean  :; forge clean
snapshot :; forge snapshot
fmt    :; forge fmt && forge fmt test/

# General test
test-aave :; forge test --match-contract Aave* -vvv
test-compound :; forge test --match-contract Compound* -vvv
test-compound-v3 :; forge test --match-contract CompoundV3* -vvv
test-steth :; forge test --match-contract stEth.*Test -vvv
test-steth-swap :; forge test --match-contract stEthSwap.*Test -vvv
test-stmatic :; forge test --match-contract stMatic.*Test -vv
test-uniswapV2 :; forge test --match-contract UniswapV2Test -vvv
test-uniswapV2swap :; forge test --match-contract UniswapV2TestSwap -vv
test-reth :; forge test --match-contract rEthTest -vvv
test-arrakis :; forge test --match-contract Arrakis_LP_Test -vvv
test-geist :; forge test --match-contract GeistERC4626ReinvestTest -vvv
test-alpaca :; forge test --match-contract AlpacaERC4626ReinvestTest -vvv
test-aavev3-uni :; forge test --match-contract AaveV3ERC4626ReinvestUniTest -vvv
test-aavev3-incentive :; forge test --match-contract AaveV3ERC4626ReinvestIncentiveTest -vvv

# Reinvest test
test-venus-reinvest :; forge test --match-contract VenusERC4626WrapperTest -vvv
test-aaveV2-reinvest :; forge test --match-contract AaveV2ERC4626ReinvestTest -vvv
test-aaveV3-reinvest :; forge test --match-contract AaveV3ERC4626ReinvestTest -vvv
test-benqi-reinvest :; forge test --match-contract BenqiERC4626ReinvestTest -vvv
test-benqiNative-reinvest :; forge test --match-contract BenqiNativeERC4626ReinvestTest -vvv
test-aaveV3-uni-reinvest :; forge test --match-contract AaveV3ERC4626ReinvestUniTest --match-test testHarvester -vvv

# Harvester tests (check tests comments)
test-aaveV3-harvest :; forge test --match-contract AaveV3ERC4626ReinvestTest --match-test testHarvester -vvv
test-venus-harvest :; forge test --match-contract VenusERC4626HarvestTest -vvv

# Uniswap tests
test-uniswapV2swap-withdraw :; forge test --match-contract UniswapV2TestSwap --match-test testDepositWithdraw -vvv
test-uniswapV2swap-localhost :; forge test --match-contract UniswapV2TestSwapLocalHost -vvv

# Benqi-Staking tests
test-benqi-staking :; forge test --match-contract BenqiERC4626StakingTest -vvvvv

# KYCDao4626 tests
test-kycdao :; forge test --match-contract kycDAO4626Test -vvv


####################
### BINANCE CHAIN ##
####################

# VENUS-BSC-USDC
deploy-venus-usdc :; forge create --rpc-url $(BSC_RPC_URL) \
				--constructor-args $(VENUS_USDC_ASSET) $(VENUS_REWARD_XVS) $(VENUS_VUSDC_CTOKEN) $(VENUS_COMPTROLLER) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/venus/VenusERC4626Reinvest.sol:VenusERC4626Reinvest

# VENUS-BSC-BUSD
deploy-venus-busd :; forge create --rpc-url $(BSC_RPC_URL) \
				--constructor-args $(VENUS_BUSD_ASSET) $(VENUS_REWARD_XVS) \
				 $(VENUS_BUSD_CTOKEN) $(VENUS_COMPTROLLER) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/venus/VenusERC4626Reinvest.sol:VenusERC4626Reinvest

##############
### POLYGON ##
##############

# AAVE-V3-POLYGON-FACTORY
deploy-aave3-polygon-factory :; forge create --rpc-url $(POLYGON_RPC_URL) \
				--constructor-args $(AAVEV3_POLYGON_LENDINGPOOL) $(AAVEV3_POLYGON_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626ReinvestFactory.sol:AaveV3ERC4626ReinvestFactory

# AAVE-V3-POLY-USDC
deploy-aave3-polygon-dai :; forge create --rpc-url $(POLYGON_RPC_URL) \
				--constructor-args $(AAVEV3_POLYGON_DAI) $(AAVEV3_POLYGON_ADAI) $(AAVEV3_POLYGON_LENDINGPOOL) $(AAVEV3_POLYGON_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V3-POLY-DAI
deploy-aave3-polygon-usdc :; forge create --rpc-url $(POLYGON_RPC_URL) \
				--constructor-args $(AAVEV3_POLYGON_USDC) $(AAVEV3_POLYGON_AUSDC) $(AAVEV3_POLYGON_LENDINGPOOL) $(AAVEV3_POLYGON_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V2-POLYGON-FACTORY
deploy-aave2-polygon-factory :; forge create --rpc-url $(POLYGON_RPC_URL) \
				--constructor-args $(AAVEV2_POLYGON_REWARDS) $(AAVEV2_POLYGON_LENDINGPOOL) $(AAVEV2_POLYGON_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626ReinvestFactory.sol:AaveV2ERC4626ReinvestFactory

# AAVE-V2-POLY-DAI
deploy-aave2-polygon-dai :; forge create --rpc-url $(POLYGON_RPC_URL) \
				--constructor-args $(AAVEV2_POLYGON_DAI) $(AAVEV2_POLYGON_ADAI) $(AAVEV2_POLYGON_REWARDS) $(AAVEV2_POLYGON_LENDINGPOOL) $(AAVEV2_POLYGON_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626Reinvest.sol:AaveV2ERC4626Reinvest

# AAVE-V2-POLY-WMATIC
deploy-aave2-polygon-wmatic :; forge create --rpc-url $(POLYGON_RPC_URL) \
				--constructor-args $(AAVEV2_POLYGON_WMATIC) $(AAVEV2_POLYGON_AWMATIC) $(AAVEV2_POLYGON_REWARDS) $(AAVEV2_POLYGON_LENDINGPOOL) $(AAVEV2_POLYGON_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626Reinvest.sol:AaveV2ERC4626Reinvest

# ARRAKIS-POLY-USDC-WMATIC-FACTORY
deploy-arrakis-poly-factory :; forge create --rpc-url $(POLYGON_RPC_URL) \
				--constructor-args $(ARRAKIS_ROUTER_CONFIG) \
				--private-key $(PRIVATE_KEY) src/arrakis/Arrakis_Factory.sol:ArrakisFactory

# ARRAKIS-POLY-WMATIC
deploy-arrakis-poly-wmatic :; forge create --rpc-url $(POLYGON_RPC_URL) \
				--constructor-args $(ARRAKIS_USDC_MATIC_GUNI_POOL) "Arrakis WMATIC/USDC LP Vault" "aLP4626" true $(ARRAKIS_ROUTER_CONFIG) 50 \
				--private-key $(PRIVATE_KEY) src/arrakis/Arrakis_Non_Native_LP_Vault.sol:ArrakisNonNativeVault

# ARRAKIS-POLY-USDC
deploy-arrakis-poly-usdc :; forge create --rpc-url $(POLYGON_RPC_URL) \
				--constructor-args $(ARRAKIS_USDC_MATIC_GUNI_POOL) "Arrakis WMATIC/USDC LP Vault" "aLP4626" false $(ARRAKIS_ROUTER_CONFIG) 50 \
				--private-key $(PRIVATE_KEY) src/arrakis/Arrakis_Non_Native_LP_Vault.sol:ArrakisNonNativeVault

#############
### AVAX ####
#############

# AAVE-V3-AVAX-FACTORY
deploy-aave3-avax-factory :; forge create --rpc-url $(AVALANCHE_RPC_URL) \
				--constructor-args $(AAVEV3_AVAX_LENDINGPOOL) $(AAVEV3_AVAX_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626ReinvestFactory.sol:AaveV3ERC4626ReinvestFactory

# AAVE-V3-AVAX-USDC
deploy-aave3-avax-usdc :; forge create --rpc-url $(AVALANCHE_RPC_URL) \
				--constructor-args $(AAVEV3_AVAX_USDC) $(AAVEV3_AVAX_AUSDC) $(AAVEV3_AVAX_LENDINGPOOL) $(AAVEV3_AVAX_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V3-AVAX-DAI
deploy-aave3-avax-dai :; forge create --rpc-url $(AVALANCHE_RPC_URL) \
				--constructor-args $(AAVEV3_AVAX_DAI) $(AAVEV3_AVAX_ADAI) $(AAVEV3_AVAX_LENDINGPOOL) $(AAVEV3_AVAX_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V2-AVAX-FACTORY
deploy-aave2-avax-factory :; forge create --rpc-url $(AVALANCHE_RPC_URL) \
				--constructor-args $(AAVEV2_AVAX_REWARDS) $(AAVEV2_AVAX_LENDINGPOOL) $(AAVEV2_AVAX_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626ReinvestFactory.sol:AaveV2ERC4626ReinvestFactory

# AAVE-V2-AVAX-DAI
deploy-aave2-avax-dai :; forge create --rpc-url $(AVALANCHE_RPC_URL) \
				--constructor-args $(AAVEV2_AVAX_DAI) $(AAVEV2_AVAX_ADAI) $(AAVEV2_AVAX_REWARDS) $(AAVEV2_AVAX_LENDINGPOOL) $(AAVEV2_AVAX_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626Reinvest.sol:AaveV2ERC4626Reinvest

# AAVE-V2-AVAX-WAVAX
deploy-aave2-avax-wavax :; forge create --rpc-url $(AVALANCHE_RPC_URL) \
				--constructor-args $(AAVEV2_AVAX_WAVAX) $(AAVEV2_AVAX_AWAVAX) $(AAVEV2_AVAX_REWARDS) $(AAVEV2_AVAX_LENDINGPOOL) $(AAVEV2_AVAX_REWARDTOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v2/AaveV2ERC4626Reinvest.sol:AaveV2ERC4626Reinvest

# BENQI-AVAX-USDC
deploy-benqi-usdc :; forge create --rpc-url $(AVALANCHE_RPC_URL) \
				--constructor-args $(BENQI_USDC_ASSET) $(BENQI_USDC_CTOKEN) $(BENQI_COMPTROLLER) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/benqi/BenqiERC4626Reinvest.sol:BenqiERC4626Reinvest

# BENQI-AVAX-WAVAX (native)
deploy-benqi-wavax :; forge create --rpc-url $(AVALANCHE_RPC_URL) \
				--constructor-args $(BENQI_WAVAX_ASSET) $(BENQI_REWARD_QI) $(BENQI_WAVAX_CETHER) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/benqi/BenqiNativeERC4626Reinvest.sol:BenqiNativeERC4626Reinvest

# BENQI-AVAX-sAVAX (liquid staking)
deploy-benqi-savax :; forge create --rpc-url $(AVALANCHE_RPC_URL) \
				--constructor-args $(BENQI_WAVAX_ASSET) $(BENQI_sAVAX_ASSET) $(BENQI_WAVAX_SAVAX_POOL) \
				--private-key $(PRIVATE_KEY) src/benqi/BenqiERC4626Staking.sol:BenqiERC4626Staking

###############
### ARBITRUM ##
###############

# AAVE-V3-ARBITRUM-FACTORY
deploy-aave3-arbitrum-factory :; forge create --rpc-url $(ARBITRUM_RPC_URL) \
				--constructor-args $(AAVEV3_ARBITRUM_LENDINGPOOL) $(AAVEV3_ARBITRUM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626ReinvestFactory.sol:AaveV3ERC4626ReinvestFactory

# AAVE-V3-ARB-DAI
deploy-aave3-arbitrum-dai :; forge create --rpc-url $(ARBITRUM_RPC_URL) \
				--constructor-args $(AAVEV3_ARBITRUM_DAI) $(AAVEV3_ARBITRUM_ADAI) $(AAVEV3_ARBITRUM_LENDINGPOOL) $(AAVEV3_ARBITRUM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V3-ARB-USDC
deploy-aave3-arbitrum-usdc :; forge create --rpc-url $(ARBITRUM_RPC_URL) \
				--constructor-args $(AAVEV3_ARBITRUM_USDC) $(AAVEV3_ARBITRUM_AUSDC) $(AAVEV3_ARBITRUM_LENDINGPOOL) $(AAVEV3_ARBITRUM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

###############
### OPTIMISM ##
###############

# AAVE-V3-OPTIMISM-FACTORY
deploy-aave3-optimism-factory :; forge create --rpc-url $(OPTIMISM_RPC_URL) \
				--constructor-args $(AAVEV3_OPTIMISM_LENDINGPOOL) $(AAVEV3_OPTIMISM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626ReinvestFactory.sol:AaveV3ERC4626ReinvestFactory

# AAVE-V3-OPT-DAI
deploy-aave3-optimism-dai :; forge create --rpc-url $(OPTIMISM_RPC_URL) \
				--constructor-args $(AAVEV3_OPTIMISM_DAI) $(AAVEV3_OPTIMISM_ADAI) $(AAVEV3_OPTIMISM_LENDINGPOOL) $(AAVEV3_OPTIMISM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

# AAVE-V3-OPT-USDC
deploy-aave3-optimism-usdc :; forge create --rpc-url $(OPTIMISM_RPC_URL) \
				--constructor-args $(AAVEV3_OPTIMISM_USDC) $(AAVEV3_OPTIMISM_AUSDC) $(AAVEV3_OPTIMISM_LENDINGPOOL) $(AAVEV3_OPTIMISM_REWARDS) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/aave-v3/AaveV3ERC4626Reinvest.sol:AaveV3ERC4626Reinvest

###############
### FANTOM ####
###############

# GEIST-FTM-DAI
deploy-geist-ftm-dai :; forge create --rpc-url $(FANTOM_RPC_URL) \
				--constructor-args $(GEIST_DAI_ASSET) $(GEIST_DAI_ATOKEN) $(GEIST_REWARDS_DISTRIBUTION) $(GEIST_LENDINGPOOL) $(GEIST_REWARD_TOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/geist/GeistERC4626Reinvest.sol:GeistERC4626Reinvest

# GEIST-FTM-USDC
deploy-geist-ftm-usdc :; forge create --rpc-url $(FANTOM_RPC_URL) \
				--constructor-args $(GEIST_USDC_ASSET) $(GEIST_USDC_ATOKEN) $(GEIST_REWARDS_DISTRIBUTION) $(GEIST_LENDINGPOOL) $(GEIST_REWARD_TOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/geist/GeistERC4626Reinvest.sol:GeistERC4626Reinvest

# GEIST-FTM-USDT
deploy-geist-ftm-usdt :; forge create --rpc-url $(FANTOM_RPC_URL) \
				--constructor-args $(GEIST_USDT_ASSET) $(GEIST_USDT_ATOKEN) $(GEIST_REWARDS_DISTRIBUTION) $(GEIST_LENDINGPOOL) $(GEIST_REWARD_TOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/geist/GeistERC4626Reinvest.sol:GeistERC4626Reinvest

# GEIST-FTM-MIM
deploy-geist-ftm-mim :; forge create --rpc-url $(FANTOM_RPC_URL) \
				--constructor-args $(GEIST_MIM_ASSET) $(GEIST_MIM_ATOKEN) $(GEIST_REWARDS_DISTRIBUTION) $(GEIST_LENDINGPOOL) $(GEIST_REWARD_TOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/geist/GeistERC4626Reinvest.sol:GeistERC4626Reinvest

# GEIST-FTM-WETH
deploy-geist-ftm-weth :; forge create --rpc-url $(FANTOM_RPC_URL) \
				--constructor-args $(GEIST_WETH_ASSET) $(GEIST_WETH_ATOKEN) $(GEIST_REWARDS_DISTRIBUTION) $(GEIST_LENDINGPOOL) $(GEIST_REWARD_TOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/geist/GeistERC4626Reinvest.sol:GeistERC4626Reinvest

# GEIST-FTM-WFTM
deploy-geist-ftm-wftm :; forge create --rpc-url $(FANTOM_RPC_URL) \
				--constructor-args $(GEIST_FTM_ASSET) $(GEIST_FTM_ATOKEN) $(GEIST_REWARDS_DISTRIBUTION) $(GEIST_LENDINGPOOL) $(GEIST_REWARD_TOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/geist/GeistERC4626Reinvest.sol:GeistERC4626Reinvest

# GEIST-FTM-CRV
deploy-geist-ftm-crv :; forge create --rpc-url $(FANTOM_RPC_URL) \
				--constructor-args $(GEIST_CRV_ASSET) $(GEIST_CRV_ATOKEN) $(GEIST_REWARDS_DISTRIBUTION) $(GEIST_LENDINGPOOL) $(GEIST_REWARD_TOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/geist/GeistERC4626Reinvest.sol:GeistERC4626Reinvest

# GEIST-FTM-WBTC
deploy-geist-ftm-wbtc :; forge create --rpc-url $(FANTOM_RPC_URL) \
				--constructor-args $(GEIST_WBTC_ASSET) $(GEIST_WBTC_ATOKEN) $(GEIST_REWARDS_DISTRIBUTION) $(GEIST_LENDINGPOOL) $(GEIST_REWARD_TOKEN) $(MANAGER) \
				--private-key $(PRIVATE_KEY) src/geist/GeistERC4626Reinvest.sol:GeistERC4626Reinvest