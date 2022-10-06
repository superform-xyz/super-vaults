// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

interface IStETH {
    function getTotalShares() external view returns (uint256);
    function submit(address) external payable returns (uint256);
    function burnShares(address,uint256) external returns (uint256);
    function approve(address,uint256) external returns (bool);
}

interface wstETH {
    function wrap(uint256) external returns (uint256);
    function unwrap(uint256) external returns (uint256);
    function getStETHByWstETH(uint256) external view returns (uint256);
}

/// @notice Modified yield-daddy version with wrapped stEth as underlying asset to avoid rebasing balance
/// @author ZeroPoint Labs
contract StETHERC4626 is ERC4626 {

    IStETH public stEth;
    wstETH public wstEth;
    address public immutable ZERO_ADDRESS = address(0);

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /// @param asset_ wstETH address (Vault has this on balance)
    /// @param stEth_ stETH (Lido contract) address
    /// @param wstEth_ wstETH contract addresss
    /// @dev @notice Beware of proxy contracts!
    /// Vault.balanceOf(asset) === wstETH
    /// All calculations are on wstETH
    /// Deposit needs to receive non-wrapped ETH to get stETH from Lido
    constructor(ERC20 asset_, IStETH stEth_, wstETH wstEth_) ERC4626(asset_, "ERC4626-Wrapped Lido stETH", "wlstETH") {
        stEth = stEth_;
        wstEth = wstEth_;
        stEth.approve(address(wstEth_), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal override {
        uint256 stEthAmount = wstEth.unwrap(assets);
        stEth.burnShares(address(this), stEthAmount);
    }

    function afterDeposit(uint256 assets, uint256 shares) internal override {
        uint256 stEthAmount = stEth.submit{value: msg.value}(ZERO_ADDRESS); /// Lido's submit() accepts only native ETH
        wstEth.wrap(stEthAmount);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function deposit(address receiver) external payable returns (uint256 shares) {
        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), msg.value);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);

        afterDeposit(msg.value, shares);
    }

    function deposit(uint256 assets, address receiver) public override payable returns (uint256 shares) {
        return deposit{value: msg.value}(receiver);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public virtual returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function totalAssets() public view virtual override returns (uint256) {
        return wstETH().balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        uint256 supply = totalSupply; 

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        uint256 supply = totalSupply; 

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }
}
