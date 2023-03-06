# Staked ETH (stEth) Lido ERC4626 Adapter

Allows users to deposit into Lido stEth Pool using WETH and receive ERC4626-stEth shares token. Shares are represented 1:1 with stEth locked on the Vault's balance. However, the withdraw/redeem functions of the adapter only output stEth tokens instead of the expected ETH and yield accrued as it would be expected from ERC4626 implementation. While preview functions accurately calculate the shares/assets value, including the yield accrued in ETH, the amount withdrawn/redeemed will only be reflected virtually in stEth tokens. 

This adapter is still work in progress and, as is, provides only base functionality of wrapping stEth token into ERC4626 interface. In near future, staking protocols are expected to open 'unstaking' directly from a staked token to the underlying. In such instance, proposed adapter will be easily extensible to such functionality.

# Future Work

Allow for direct stEth deposits into the Vault and mint equal amounts of ERC4626-stEth tokens.