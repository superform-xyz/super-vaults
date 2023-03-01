# Compound protocol ERC4626 Adapters

All vaults have same workflow in deposit and withdraw. the main difference is how the rewards are claimed, reinvested and mechanisms and protocols used for reinvesting.

-   [CompoundV2ERC4626Wrapper](CompoundV2ERC4626Wrapper.sol):
    -   Interacts with CompoundV2 protocol to deposit, withdraw assets and claim rewards.
    -   `harvest` method is external and takes `minAmountOut_` as input, claims the rewards and reinvests.
    -   `setRoute` is a permissioned method that should set the pairs on which the swaps from [ claimedRewards -> middle token (if any) -> asset ] happen.
          > Note:
          > 
          >     - Choose the pairs which have high liquidity for swaps to avoid slippages
          >     - Harvest should be called only after routes are set.
          >     - On chain pair swaps are susceptible to price manipulation that can happen before or after the transaction if minAmountOut is not used efficiently.
    -   harvest logic checks for minimum amount to be reinvested not the output of intermediate swaps on pairs.

-   [CompoundV3ERC4626Wrapper](CompoundV3ERC4626Wrapper.sol):
    -   Interacts with CompoundV3 protocol to deposit, withdraw assets and claim rewards.
    -   `harvest` method is external and takes `minAmountOut_` as input, claims the rewards and reinvests.
    -   Reinvesting logic uses uniswap v3 router to make the swap from reward to asset using the swapPath set by the `setRoutes` method.
    -   `setRoute` is a permissioned method that should set the swap path on which the swaps from [ claimedRewards -> middle token (if any) -> asset ] happen.
          > Note:
          >
          >     - Choose the pairs which have high liquidity for swaps to avoid slippages
          >     - Harvest should be called only after swap paths are set.
          >     - swaps are susceptible to price manipulation that can happen before or after the transaction if minAmountOut is not used efficiently.