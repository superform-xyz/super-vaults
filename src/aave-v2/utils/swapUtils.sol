// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

interface IPair {
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

library DexSwap {
    using SafeTransferLib for ERC20;

    /**
     * @notice Swap directly through a Pair
     * @param amountIn input amount
     * @param fromToken address
     * @param toToken address
     * @param pairToken Pair used for swap
     * @return output amount
     */
    function swap(
        uint256 amountIn,
        /// uint256 amountOutMin == expected amountOut2 out of above amountIn - slippage, this needs to be off-chain because we need to use reserve0/1 read before sending harvest() transaction
        address fromToken,
        address toToken,
        address pairToken
    ) internal returns (uint256) {
        IPair pair = IPair(pairToken);
        (address token0, ) = sortTokens(fromToken, toToken);
        /// bot can manipulate reserve0 & reserve1 from which we get amountOut2, in other words for same amountIn we can get less than expected amountOut2
        /// @dev this is where we can check amountOut2 >= minAmountOut, swap is made against current reserves state
        /// exactly what router does https://github.com/Uniswap/v2-periphery/blob/0335e8f7e1bd1e8d8329fd300aea2ef2f36dd19f/contracts/UniswapV2Router02.sol#L231
        /// if now amountOut2 < minAmountOut, we can revert before transfer and accept also "worst-than-perfect execution" (which probably bots will try to exploit)
        /// rationale: it works because reserves in the next block than sent transaction can be different (or, manipulated by bots)
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        if (token0 != fromToken) (reserve0, reserve1) = (reserve1, reserve0);
        uint256 amountOut1 = 0;
        uint256 amountOut2 = getAmountOut(amountIn, reserve0, reserve1);
        /// require(amountOut2 <= minAmountOut, "slippage too high"")
        if (token0 != fromToken)
            (amountOut1, amountOut2) = (amountOut2, amountOut1);
        ERC20(fromToken).safeTransfer(address(pair), amountIn);
        pair.swap(amountOut1, amountOut2, address(this), new bytes(0));
        return amountOut2 > amountOut1 ? amountOut2 : amountOut1;
    }

    /**
     * @notice Given an input amount of an asset and pair reserves, returns maximum output amount of the other asset
     * @dev Assumes swap fee is 0.30%
     * @param amountIn input asset
     * @param reserveIn size of input asset reserve
     * @param reserveOut size of output asset reserve
     * @return maximum output amount
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * (reserveOut);
        uint256 denominator = (reserveIn * 1000) + (amountInWithFee);
        return numerator / (denominator);
    }

    function _getMinAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 _maxSlippage) internal pure returns (uint256 _minAmountOut) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * (reserveOut);
        uint256 denominator = (reserveIn * 1000) + (amountInWithFee);
        uint256 _amountOut = numerator / (denominator);
        ///@dev _maxSlippage is per 1000 basis points - 50 is 0.05%, 
        _minAmountOut = _amountOut - ((_amountOut * _maxSlippage) / 1000);
    }


    /**
     * @notice Given two tokens, it'll return the tokens in the right order for the tokens pair
     * @dev TokenA must be different from TokenB, and both shouldn't be address(0), no validations
     * @param tokenA address
     * @param tokenB address
     * @return sorted tokens
     */
    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address, address)
    {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}
