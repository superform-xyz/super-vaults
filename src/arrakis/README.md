# Arrakis LP Vault (based on Uniswap v3 LP)

The following steps describe the workflow for the smart contract:

    - Users can deposit either tokenA or tokenB from any one of the Uniswap v3 pools into the `Arrakis LP Vault`.
    - The `afterDeposit` internal method then swaps a part of the deposited token (tokenA/tokenB) to its complementary token (tokenB/tokenA). <br>The swapAmount for the deposited token is calculated based on the current active position maintained by the Arrakis vault.
    - The Arrakis router's `addLiquidityAndStake` method is used to add liquidity to `gUniPool`, which is an Arrakis vault. The receipt tokens are then staked onto a `guage` contract that provides staking rewards.
    - Users can withdraw their position to the deposited asset token of the Uniswap v3 pool tokens (i.e., tokenA or tokenB).
    - The `beforeWithdraw` internal method withdraws the staked position on the `guage` contract and removes liquidity from `gUnipool`, which returns both tokenA and tokenB according to the liquidity position maintained by the Arrakis vault at the point of withdrawal.
    - From the returned tokens, any `non_asset` token is swapped to the `asset` token and sent to the receiver.



> Note: The above steps are performed within the smart contract, and users interact with the contract using appropriate function calls.
>
>  Deposit and withdraw are susceptible to on-chain manipulation, as deposit and withdraw do on-chain swaps, deposit and withdraw tokens    received could be manipulated before or after the transaction.
>  `Arrakis_Factory.sol` can be used to deploy vaults for both the tokens of an Uniswap V3 pool.
