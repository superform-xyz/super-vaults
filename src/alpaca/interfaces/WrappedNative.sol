// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface WrappedNative {
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}
