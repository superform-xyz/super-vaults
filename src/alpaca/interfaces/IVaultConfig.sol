// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

interface IVaultConfig {
    /// @dev Return the bps rate for reserve pool.
    function getReservePoolBps() external view returns (uint256);
}
