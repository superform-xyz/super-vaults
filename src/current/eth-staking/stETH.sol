// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

abstract contract IStETH is ERC20 {
    function getTotalShares() external view virtual returns (uint256);
    function submit(address) external payable returns (uint256);
}

interface wstETH {
    function wrap(uint256) external returns (uint256);
    function unwrap(uint256) external returns (uint256);
}

/// @title StETHERC4626
/// @author zefram.eth
/// @notice ERC4626 wrapper for Lido stETH
/// @dev Uses stETH's internal shares accounting instead of using regular vault accounting
/// since this prevents attackers from atomically increasing the vault's share value
/// and exploiting lending protocols that use this vault as a borrow asset.
/// @notice This wrappers isn't suited to SuperForm needs
/// Case 1: User gives BUSDC on BSC and reqs wstETH (no-rebase) on ETH with Shares minted on BSC
/// We need Zap contract (for this & "double sided" pools)
contract StETHERC4626 is ERC4626 {
    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /// @param asset_ wstETH address (Vault has this on balance)
    /// Vault.balanceOf(asset) === wstETH
    /// All calculations are on wstETH
    /// Deposit needs to send ETH to get stETH
    constructor(ERC20 asset_) ERC4626(asset_, "ERC4626-Wrapped Lido stETH", "wlstETH") {
        IStETH.approve(wstETH, type(uint256).max);
    }

    /// -----------------------------------------------------------------------
    /// Getters
    /// -----------------------------------------------------------------------

    function stETH() public view returns (IStETH) {
        return IStETH(address(asset));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256 shares) internal virtual {
        wstETH.unwrap(assets);
    }

    function afterDeposit(uint256 assets, uint256 shares) internal virtual {
        uint256 stEthAmount = IStETH.submit(0){msg.value}; /// this accepts eth with msg.value, not ERC20 token
        wstETH.wrap(stEthAmount);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    function deposit(address receiver) public payable returns (uint256 shares) {
        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function deposit(uint256 assets, address receiver) public override payable returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        uint256 assets = msg.value;
        super.deposit(assets, receiver);
    }

    function totalAssets() public view virtual override returns (uint256) {
        return stETH().balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view virtual override returns (uint256) {
        uint256 supply = stETH().totalSupply();

        return supply == 0 ? assets : assets.mulDivDown(stETH().getTotalShares(), supply);
    }

    function convertToAssets(uint256 shares) public view virtual override returns (uint256) {
        uint256 totalShares = stETH().getTotalShares();

        return totalShares == 0 ? shares : shares.mulDivDown(stETH().totalSupply(), totalShares);
    }

    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        uint256 totalShares = stETH().getTotalShares();

        return totalShares == 0 ? shares : shares.mulDivUp(stETH().totalSupply(), totalShares);
    }

    function previewWithdraw(uint256 assets) public view virtual override returns (uint256) {
        uint256 supply = stETH().totalSupply();

        return supply == 0 ? assets : assets.mulDivUp(stETH().getTotalShares(), supply);
    }
}
