// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

interface IStETH {
    function getTotalShares() external view returns (uint256);

    function submit(address) external payable returns (uint256);

    function burnShares(address, uint256) external returns (uint256);

    function approve(address, uint256) external returns (bool);
}

interface wstETH {
    function wrap(uint256) external returns (uint256);

    function unwrap(uint256) external returns (uint256);

    function getStETHByWstETH(uint256) external view returns (uint256);

    function balanceOf(address) external view returns (uint256);
}

interface IWETH {
    function wrap(uint256) external payable returns (uint256);

    function unwrap(uint256) external returns (uint256);
}

/// @notice Modified yield-daddy version with wrapped stEth as underlying asset to avoid rebasing balance
/// @author ZeroPoint Labs
contract StETHERC4626 is ERC4626 {
    IStETH public stEth;
    wstETH public wstEth;
    IWETH public weth;
    address public immutable ZERO_ADDRESS = address(0);

    /// -----------------------------------------------------------------------
    /// Libraries usage
    /// -----------------------------------------------------------------------

    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    /// @param weth_ weth address (Vault's underlying / deposit token)
    /// @param stEth_ stETH (Lido contract) address
    /// @param wstEth_ wstETH contract addresss
    /// @dev @notice Beware of proxy contracts!
    /// Vault.balanceOf(asset) === wstETH
    /// All calculations are on wstETH
    /// Deposit needs to receive non-wrapped ETH to get stETH from Lido
    constructor(
        address weth_,
        address stEth_,
        address wstEth_
    ) ERC4626(ERC20(weth_), "ERC4626-Wrapped Lido stETH", "wlstETH") {
        stEth = IStETH(stEth_);
        wstEth = wstETH(wstEth_);
        weth = IWETH(weth_);
        stEth.approve(address(wstEth_), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function beforeWithdraw(uint256 assets, uint256) internal override {
        uint256 stEthAmount = wstEth.unwrap(assets);
        stEth.burnShares(address(this), stEthAmount);
    }

    function afterDeposit(uint256 ethAmount, uint256) internal override {
        uint256 stEthAmount = stEth.submit{value: ethAmount}(ZERO_ADDRESS); /// Lido's submit() accepts only native ETH
        wstEth.wrap(stEthAmount);
    }

    /// -----------------------------------------------------------------------
    /// ERC4626 overrides
    /// -----------------------------------------------------------------------

    /// Standard ERC4626 deposit can only accept ERC20
    /// Vault's underlying is WETH (ERC20), Lido expects ETH (Native), we make wraperooo magic
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        asset.safeTransferFrom(msg.sender, address(this), assets);

        uint256 ethAmount = weth.unwrap(assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(ethAmount, shares);
    }

    /// Deposit function accepting ETH (Native) directly
    function deposit(address receiver) public payable returns (uint256 shares) {
        require(msg.value != 0, "0");

        require((shares = previewDeposit(msg.value)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, msg.value, shares);

        afterDeposit(msg.value, shares);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);

        uint256 ethAmount = weth.unwrap(assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(ethAmount, shares);
    }

    /// @dev payable mint() is difficult to implement, probably should be dropped fully
    /// we can live with mint() being only available through weth
    // function mint(uint256 shares, address receiver, bool isPayable) public payable returns (uint256 assets) {
    //     require((ethAmount = previewMint(shares)) == msg.value, "NOT_ENOUGH");
    //     _mint(receiver, shares);
    //     emit Deposit(msg.sender, receiver, ethAmount, shares);
    //     afterDeposit(msg.value, shares);
    // }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        SafeTransferLib.safeTransferETH(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        SafeTransferLib.safeTransferETH(receiver, assets);
    }

    function totalAssets() public view virtual override returns (uint256) {
        return wstEth.balanceOf(address(this));
    }

    function convertToShares(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewMint(uint256 shares)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 supply = totalSupply;

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }
}
