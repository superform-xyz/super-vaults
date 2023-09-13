// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { IBERC20 } from "./IBERC20.sol";

/// @notice Get up to date cToken data without mutating state.
/// @notice Forked from Transmissions11 (https://github.com/transmissions11/libcompound) to upgrade version
/// @author ZeroPoint Labs
library LibBCompound {
    using FixedPointMathLib for uint256;

    error RATE_TOO_HIGH();

    function viewUnderlyingBalanceOf(IBERC20 cToken, address user) internal view returns (uint256) {
        return cToken.balanceOf(user).mulWadDown(viewExchangeRate(cToken));
    }

    function viewExchangeRate(IBERC20 cToken) internal view returns (uint256) {
        uint256 accrualBlockNumberPrior = cToken.accrualBlockNumber();

        if (accrualBlockNumberPrior == block.number) {
            return cToken.exchangeRateStored();
        }

        uint256 totalCash = cToken.underlying().balanceOf(address(cToken));
        uint256 borrowsPrior = cToken.totalBorrows();
        uint256 reservesPrior = cToken.totalReserves();

        uint256 borrowRateMantissa = cToken.interestRateModel().getBorrowRate(totalCash, borrowsPrior, reservesPrior);

        if (borrowRateMantissa > 0.0005e16) revert RATE_TOO_HIGH(); // Same as borrowRateMaxMantissa in
            // CTokenInterfaces.sol

        uint256 interestAccumulated =
            (borrowRateMantissa * (block.number - accrualBlockNumberPrior)).mulWadDown(borrowsPrior);

        uint256 totalReserves = cToken.reserveFactorMantissa().mulWadDown(interestAccumulated) + reservesPrior;
        uint256 totalBorrows = interestAccumulated + borrowsPrior;
        uint256 totalSupply = cToken.totalSupply();

        return totalSupply == 0
            ? cToken.initialExchangeRateMantissa()
            : (totalCash + totalBorrows - totalReserves).divWadDown(totalSupply);
    }
}
