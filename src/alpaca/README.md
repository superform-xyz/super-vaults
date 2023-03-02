# Alpaca Finance ERC4626 Adapter Extended

Build upon yield-daddy's AaveV2ERC4626 and super-vault's AaveV2ERC4626Reinvest adapters to support the ERC4626 interface on any given Alpaca Finance market. In addition to this, adapter use the capability to stake received Alpaca LP-Tokens into the reward pool for secondary APY in one deposit transaction. The vault's totalAssets() function reflects the value of all tokens deposited into a market, which includes the base APY as well as rewards earned from secondary staking into the Alpaca rewards distribution. 

Note that the current version of the vault is not yet optimized for on-chain usage.