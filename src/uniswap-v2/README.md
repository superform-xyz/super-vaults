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

    - addLiquidity
        - previewDeposit
    - removeLiquidity
        - previewWithdraw

Outputs

    - token0 safeTransferred 
    - token0 & token1 safeTransferred
