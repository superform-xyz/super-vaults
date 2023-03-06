# Geist Finance ERC4626 Adapter (WIP)

Build upon yield-daddy's AaveV2ERC4626 and super-vault's AaveV2ERC4626Reinvest adapters to support the ERC4626 interface on any given Geist Finance market. Currently, harvest() function is non-operational as Vault is not vesting LP-token in Geist Reward Pool. A temporary design choice to provide better UX over "Timelocked" Vaults (in case of Geist for 3 months).

Note that the current version of the vault is not yet optimized for on-chain usage.