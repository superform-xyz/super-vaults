// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;
interface WrappedNative {
    function deposit() external payable;
    function withdraw(uint wad) external;
}