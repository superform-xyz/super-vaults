// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ICERC20} from "./ICERC20.sol";

interface IComptroller {
    struct VenusMarketState {
        /// @notice The market's last updated venusBorrowIndex or venusSupplyIndex
        uint224 index;
        /// @notice The block number the index was last updated at
        uint32 block;
    }

    function getXVSAddress() external view returns (address);

    function getAllMarkets() external view returns (ICERC20[] memory);

    function allMarkets(uint256 index) external view returns (ICERC20);

    function claimVenus(address holder) external;

    function venusSupplyState(address cToken)
        external
        view
        returns (VenusMarketState memory);

    function venusSupplierIndex(address cToken, address supplier)
        external
        view
        returns (uint256);

    function venusAccrued(address user)
        external
        view
        returns (uint256 venusRewards);

    function mintGuardianPaused(ICERC20 cToken) external view returns (bool);

    function getAccountLiquidity(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}
