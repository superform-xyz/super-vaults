# Staked Rocket ETH (rEth) Rocket Pool

Allows users to deposit into Rocket Pool rEth using WETH and receive ERC4626-rEth shares token. Shares are represented 1:1 with rEth locked on the Vault's balance. However, the withdraw/redeem functions of the adapter only output rEth tokens instead of the expected ETH and yield accrued as it would be expected from ERC4626 implementation. While preview functions accurately calculate the shares/assets value, including the yield accrued in ETH, the amount withdrawn/redeemed will only be reflected virtually in rEth tokens. 

Rocket Pools are built on an upgradeable architecture, and this adapter accounts for potential contract storage changes, ensuring that it is safe to use for every deposit. Moreover, the Vault performs a check to ensure that free slots for staking are available.

This adapter is still work in progress and, as is, provides only base functionality of wrapping rEth token into ERC4626 interface. In near future, staking protocols are expected to open 'unstaking' directly from a staked token to the underlying. In such instance, proposed adapter will be easily extensible to such functionality.

# Risks

`uint256 rEthReceived = depositBalance - startBalance;` - Rocket Pool does not return amount of rEth received and suggested solution is to find the difference in balances before and after deposit. Such method is prone to inflation attack.

# TODO:

- Allow direct rEth deposit into the Vault (accept rEth > mint equal amount of ERC4626-rEth)