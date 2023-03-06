# Benqi Markets & Staking ERC4626 Adapters

`BeniqERC4626Reinvest.sol` - Standard ERC4626 adapter over any available Benqi Market. Benqi is a Compound fork protocol on the "market" level. Allowing to deposit and supply assets to the Benqi's cToken. Build on yield-daddy example, extended with multiple rewards harvesting.

`BenqiERC4626Staking.sol` - Benqi's version of a liquid staking service for AVAX native token. Originally forked from Lido with significant changes to the unstaking process. Unstaking isn't currently implemented and adapter follows the same pattern of action as remaining liquid staking derivatives wrappers like Lido and RocketPool.

`BenqiNativeERC4626Reinvest.sol` - Standard ERC4626 adapter over available Benqi AVAX Market (non-ERC20 market). Allows to also deposit native AVAX token directly (not a part of ERC4626 interface).

# Future Works

 Extend `BenqiERC4626Staking.sol` with a combined Timelock and unstake capability, allowing to exit from the Vault to AVAX token with yield accrued directly.