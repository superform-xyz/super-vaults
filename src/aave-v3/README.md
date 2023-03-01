#  AAVE v3 protocol ERC4626 Adapters

All vaults have same workflow in deposit and withdraw. the main difference is how the rewards are reinvested and mechanisms and protocols used for reinvesting.

-   [`AaveV3ERC4626Reinvest`](AaveV3ERC4626Reinvest.sol):
    -   `harvest` method is external and takes `minAmountOuts_` as input, claims the rewards and reinvests
    -   `setRoutes` is a permissioned method that should set the pairs on which the swaps from [ claimedRewards -> middle token (if any) -> asset ] happen.
          > Note:
          > 
          >     - Choose the pairs which have high liquidity for swaps to avoid slippages
          >     - Harvest should be called only after routes are set.
          >     - On chain pair swaps are susceptible to price manipulation that can happen before or after the transaction if minAmountOut is not used efficiently.
    -   harvest logic checks for minimum amountOut for each of the reward to asset swap as aave v3 can have multiple rewards.
    -   `harvest` method reverts if any of the minAmountOut is not met after swap, make sure to keep rest of the rewards minAmountOuts as 0 if they are not claimed nor swapped.
-   [`AaveV2ERC4626ReinvestIncentive`](AaveV2ERC4626ReinvestIncentive.sol)
    -   Extending `AaveV3ERC4626Reinvest` to incentivize reinvesting by a user by providing a portion on reinvesting amount.  
    -   `REINVEST_REWARD_BPS` determines how much a harvest caller would receive for reinvesting.
    -   `updateReinvestRewardBps` permission methods can be used to set the above factors.

-   [`AaveV3ERC4626ReinvestUni`](AaveV3ERC4626ReinvestUni.sol)
    -   This is an extended implementation of `AaveV3ERC4626Reinvest` to use uniswap for harvest reward token swaps instead of on-chain pair swaps.
    -   `harvest` method is external and takes `minAmountOuts_` as input, claims the rewards and reinvests
    -   `setRoutes` is a permissioned method that should set the swap path on which the swaps from [ claimedRewards -> middle token (if any) -> asset ] happen.
          > Note:
          >
          >     - Choose the pairs which have high liquidity for swaps to avoid slippages
          >     - Harvest should be called only after swap paths are set.
          >     - swaps are susceptible to price manipulation that can happen before or after the transaction if minAmountOut is not used efficiently.
    -   harvest logic checks for minimum amountOut for each of the reward to asset swap as aave v3 can have multiple rewards.
    -   `harvest` method reverts if any of the minAmountOut is not met after swap, make sure to keep rest of the rewards minAmountOuts as 0 if they are not claimed nor swapped.
    -   `harvest` uses uniswap v3 router to make the swap from reward to asset using the swapPath set by the `setRoutes` method.