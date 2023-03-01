// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

interface IVaultConfig {
    /// @dev Return the bps rate for reserve pool.
    function getReservePoolBps() external view returns (uint256);
}
