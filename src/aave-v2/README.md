#  AAVE v2 protocol ERC4626 Adapters

All vaults have same workflow in deposit and withdraw. the main difference is how the rewards are reinvested and mechanisms of reinvesting.

-   [`AaveV2ERC4626Reinvest`](AaveV2ERC4626Reinvest.sol):
    -   `harvest` method is external and takes `minAmountOut_` as input, claims the rewards and reinvests
    -   `setRoutes` is a permissioned method that should set the pairs on which the swaps from [ claimedRewards -> middle token (if any) -> asset ] happen.
          > Note:
          > 
          > -   Choose the pairs which have high liquidity for swaps to avoid slippages
          > -   Harvest should be called only after routes are set.
    -   harvest logic checks for minimum amount to be reinvested not the output of intermediate swaps on pairs
-   [`AaveV2ERC4626ReinvestIncentive`](AaveV2ERC4626ReinvestIncentive.sol)
    -   Extending `AaveV2ERC4626Reinvest` to incentivize reinvesting by a user by providing a portion on reinvesting amount.  
    -   `REINVEST_REWARD_BPS` determines how much a harvest caller would receive for reinvesting.
    -   `MIN_TOKENS_TO_REINVEST` determines minimum amount of asset that can be deposited in a reinvest.
    -   `updateMinTokensToHarvest` and `updateReinvestRewardBps` permission methods can be used to set the above factors.