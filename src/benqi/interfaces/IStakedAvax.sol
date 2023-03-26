// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.19;

interface IStakedAvax {

    struct UnlockRequest {
        // The timestamp at which the `shareAmount` was requested to be unlocked
        uint startedAt;
        // The amount of shares to burn
        uint shareAmount;
    }

    function getSharesByPooledAvax(uint256 avaxAmount)
        external
        view
        returns (uint256);

    function getPooledAvaxByShares(uint256 shareAmount)
        external
        view
        returns (uint256);

    function approve(address, uint256) external returns (bool);

    function balanceOf(address) external view returns (uint256);

    function submit() external payable returns (uint256);

    /// NOTE: Using Benqi sAVAX as example of a Vault with 15d cooldown period
    /// NOTE: https://snowtrace.io/address/0x0ce7f620eb645a4fbf688a1c1937bc6cb0cbdd29#code (sAVAX)
    /// NOTE: Notice, this requires additional logic on FORM level itself
    /// NOTE: Owner first submits request for unlock and only after 15d can withdraw
    function requestUnlock(uint shareAmount) external;

    /// NOTE: Using Benqi sAVAX as example of a Vault with 15d cooldown period
    /// NOTE: Useful for API to keep track of when user can withdraw
    function cooldownPeriod() external view returns (uint256);

    /// NOTE: Using Benqi sAVAX as example of a Vault with 15d cooldown period
    function userUnlockRequests(address owner, uint256 index) external view returns (UnlockRequest memory);

    /**
     * @notice Get the number of active unlock requests by user
     * @param user User address
     */
    function getUnlockRequestCount(address user) external view returns (uint);

}
