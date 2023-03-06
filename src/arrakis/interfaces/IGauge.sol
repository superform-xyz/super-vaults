// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IGauge {
    function withdraw(uint256 amount) external;

    function balanceOf(address account) external view returns (uint256);
}
