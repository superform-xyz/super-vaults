# Uniswap V2 Pool ERC4626 Adapter

`./swap-built-in/UniswapV2ERC4626Swap.sol`

Allows to deposit into Uniswap V2 Pool using token0 or token1 and receive Uniswap LP-token representation wrapped in ERC4626 functionality. Vault calculates optimal amount for splitting token to two required tokens for deposit operation. For withdraw, Vault simulates expected value of token0 or token1 (depending which Vault is used) within a block. Vault performs `swapJoin()` and `swapExit()` operations to swap to appropraite amounts of token0 and token1 required amounts. Can be instantly deployed for token0 and token1 of UniswapV2Pair with a use of `UniswapV2ERC4626PoolFactory.sol`

`./no-swap/UniswapV2.sol`

Allows to deposit into Uniswap V2 Pool by 'yanking' both token0 and token1 from user address in exchange for Uniswap LP-token representation wrapped in ERC4626 functionality. Uniswap's Pair token (LP-Token) is used for internal accoutning and virtual amounts of token0 and token1 are expected to be transfered by user to a Vault address in exchange for specified earlier amount of Pair token to receive. 

# Observations (NEW!)

`previewDeposit()` can be only trusted as much as for a single block. if caller is EOA, he can perform off-chain validation of `previewDeposit()` current value against past value(s). we can't expect the same from the contract account.

user can shoot his foot off if blindly integrating with this contracts. that is because uniswapV2Pair reserves are easy to manipulate for one block. however, manipulation can only lead to smaller output amount of shares, but not the loss of funds across the vault or other accounting errors, as UniswapV2ERC4626Swap adapter is operating on 1:1 with LP-Token of Uniswap, getting more of LP-Token or less is only important for the caller and won't affect deposit/withdraw scheme.

### Both contracts are WIP / Experimental phase

TODO: Uniswap Reserves Manipulation - critical fix!
TODO: Slippage / invariant for deposit/withdraw flow

# Design notes (OLD!)

We can look at the problem of creating a single asset ERC4626 adapter over Uniswap's V2 double asset Pool as 'blackbox' automaton build only out of simple input/outputs and transforming functions.

> The FSM can change from one state to another in response to some inputs; the change from one state to another is called a transition. An FSM is defined by a list of its states, its initial state, and the inputs that trigger each transition.

> A state is a description of the status of a system that is waiting to execute a transition. A transition is a set of actions to be executed when a condition is fulfilled or when an event is receive

Input variable is token (or tokens) to the ERC4626 Vault
Output variable is LP-token of ERC4626
Uniswap Pool interface within ERC4626 is a transition function (addLiquidity, removeLiquidity)

Acceptors

    - Accept token0
    - Accept token0 swap amount to generate token1
        - ... all that is neccessary for it falls under 2nd order transforming functions inside of a 'blackbox'

State (possible)

    - token0 received
    - token0 swapped to token0 & token1
    - pairToken received
    - token0 & token1 from pairToken on balance
    - token0 (from t0+t1 after transforming functions like swap)
    - token0 & token1 withdraw

External Transducers

    - addLiquidity
        - previewDeposit
    - removeLiquidity
        - previewWithdraw

Internal Transducers

    - accounting `get()` functions for assets/shares/lp maniuplation

Outputs

    - token0 safeTransferred 
    - OR token0 & token1 safeTransferred (optional)
