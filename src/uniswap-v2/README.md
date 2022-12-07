# WIP / Experimental phase

# Design notes

We can look at the problem of creating a single asset ERC4626 adapter over Uniswap's V2 double asset Pool as automaton with most interest of input & output variables (tokens).

> The FSM can change from one state to another in response to some inputs; the change from one state to another is called a transition. An FSM is defined by a list of its states, its initial state, and the inputs that trigger each transition.

> A state is a description of the status of a system that is waiting to execute a transition. A transition is a set of actions to be executed when a condition is fulfilled or when an event is receive

Input variable is token (or tokens) to the ERC4626 balance
Output variable is LP-token of ERC4626
Uniswap Pool interface within ERC4626 is a transition function (addLiquidity, removeLiquidity)

Acceptors

    - Accept token0
    - Accept token0 swap amount to generate token1

State (possible)

    - token0 received
    - token0 swapped to token0 & token1
    - pairToken received
    - token0 & token1 from pairToken on balance
    - token0 withdraw, token1 addLiquidity back
    - token0 & token1 withdraw

Transducers

    - addLiquidity (called 2x if we redeposit leftover)
        - previewDeposit
    - removeLiquidity
        - previewWithdraw

Outputs

    - token0 safeTransferred 
    - token0 & token1 safeTransferred

# Problems

1. If we accept only token0 as input and token0 as output, shares value is hard to reflect because it's virtual in its nature. Meaning, to get real value we need multiple values simulated. 
    - token0 to token0/token1 to lpAmount to token0/token1 output to token0 swapped to token0/token1 added again

2. When user joins valut with 100 DAI, its split in 50DAI/50USDC. When user wants to exit using his shares (reflecting 50/50) we need to exit whole position. In contrary to Curve, you can't exit only with single token on Uni. It leads to leftover amounts.

AD. 2: Solved by allowing to safeTransfer token0 & token1, previews are not fully implemented and right now serve as indication of how much we expect to reedem. underlying token0 (or token1) is just abstracted as virtual amount, a receiver can be external ZapOut contract. 