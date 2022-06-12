// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {KeeperCompatibleInterface} from "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AggregatorV2V3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import {IERC4626} from "./IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title YeetVault
/// @notice A smart vault that manages a position in a risky stablecoin (e.g. UST),
///     and automatically liquidates the position into a safe-haven asset (e.g. USDC) in
///     the event of a possible depegging scenario.
///     A possible depegging event is characterised by the mean price over the last n
///     rounds of a Chainlink price feed going below a specified liquidation threshold.
///     When a depegging event is detected, a keeper triggers the state to `Liquidatable`
///     and anyone can take this entire vault of the risky stablecoin by exchanging
///     safe-haven assets at the rate of the stop-loss. The liquidatoooor keeps any profit
///     resulting from the price delta between the liquidation threshold and the stop-loss.
contract YeetVault is
    IERC4626,
    ERC20,
    ReentrancyGuard,
    KeeperCompatibleInterface
{
    using SafeERC20 for ERC20;

    event WithdrawSafeHavenAsset(
        address caller,
        address receiver,
        address owner,
        uint256 safeHavenAssetAmount,
        uint256 shares
    );

    event VaultLiquidatableTriggered(
        uint256 blockNumber,
        uint256 timestamp,
        uint256 meanPrice
    );

    enum VaultStatus {
        Open,
        Liquidatable,
        Liquidated
    }

    /// @notice State of the vault
    VaultStatus public vaultState = VaultStatus.Open;

    /// @notice Block number at which the vault was triggered for liquidation
    uint256 public vaultLiquidatableAt;

    /// @notice The stablecoin you wanna degen into
    address public immutable asset;

    /// @notice The asset that the protocol will convert into in a liquidation event
    ERC20 public immutable safeHavenAsset;

    /// @notice Number of price feed updates when comparing mean price to liquidation threshold
    uint256 public immutable nOracleRounds;

    /// @notice The price of ASSET/USDC at which liquidation is enabled, specified in the feed's decimals
    uint256 public immutable liquidationThreshold;

    /// @notice The minimum price of ASSET/USDC at which this vault will accept when in liquidation
    uint256 public immutable stopLoss;

    /// @notice Chainlink price feed for <ASSET>/USDC
    AggregatorV2V3Interface public immutable feed;

    constructor(
        string memory vaultName,
        string memory vaultSymbol,
        address asset_,
        address safeHavenAsset_,
        uint256 nOracleRounds_,
        uint256 liquidationThreshold_,
        uint256 stopLoss_,
        address feed_
    ) ERC20(vaultName, vaultSymbol) {
        asset = asset_;
        feed = AggregatorV2V3Interface(feed_);
        nOracleRounds = nOracleRounds_;
        liquidationThreshold = liquidationThreshold_;
        stopLoss = stopLoss_;
        safeHavenAsset = ERC20(safeHavenAsset_);
    }

    modifier isOpenState() {
        require(vaultState == VaultStatus.Open, "Vault not open");
        _;
    }

    function totalAssets() public view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return 0;
        return (shares * totalAssets()) / _totalSupply;
    }

    function convertSharesToSafeHavenAssets(uint256 shares)
        public
        view
        returns (uint256)
    {
        uint256 totalSupply_ = totalSupply();
        if (totalSupply_ == 0) return 0;
        return
            (shares * safeHavenAsset.balanceOf(address(this))) / totalSupply_;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        uint256 _totalAssets = totalAssets();
        if (_totalAssets == 0 || _totalSupply == 0) return assets;
        return (assets * _totalSupply) / _totalAssets;
    }

    function maxDeposit(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return convertToShares(assets);
    }

    function deposit(uint256 assets, address receiver)
        public
        isOpenState
        returns (uint256)
    {
        uint256 shares = convertToShares(assets);
        ERC20(asset).safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);

        return shares;
    }

    function deposit(uint256 assets) external returns (uint256) {
        return deposit(assets, msg.sender);
    }

    function maxMint(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares) external view returns (uint256) {
        uint256 assets = convertToAssets(shares);
        if (assets == 0 && totalAssets() == 0) return shares;
        return assets;
    }

    function mint(uint256 shares, address receiver)
        public
        isOpenState
        returns (uint256)
    {
        uint256 assets = convertToAssets(shares);

        if (totalAssets() == 0) assets = shares;

        ERC20(asset).safeTransferFrom(msg.sender, address(this), assets);

        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);

        return assets;
    }

    function mint(uint256 shares) external returns (uint256) {
        return mint(shares, msg.sender);
    }

    function maxWithdraw(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewWithdraw(uint256 assets) external view returns (uint256) {
        uint256 shares = convertToShares(assets);
        if (totalSupply() == 0) return 0;
        return shares;
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public returns (uint256) {
        uint256 shares = convertToShares(assets);

        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);

        ERC20(asset).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return shares;
    }

    function withdraw(uint256 assets, address receiver)
        external
        returns (uint256)
    {
        return withdraw(assets, receiver, msg.sender);
    }

    function withdraw(uint256 assets) external returns (uint256) {
        return withdraw(assets, msg.sender, msg.sender);
    }

    function maxRedeem(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function previewRedeem(uint256 shares) external view returns (uint256) {
        return convertToAssets(shares);
    }

    /// @notice Redeem shares in the vault for safe haven assets. Only callable once
    ///  the vault has been liquidated.
    /// @param shares Amount of shares to redeem
    /// @param receiver Where to send the redeemed safe haven assets
    /// @param owner Owner of the shares
    function redeemSafeHavenAssets(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256) {
        require(
            vaultState == VaultStatus.Liquidated,
            "Vault is not in liquidated state"
        );

        uint256 safeHavenAssetAmount = convertSharesToSafeHavenAssets(shares);

        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);

        safeHavenAsset.safeTransfer(receiver, safeHavenAssetAmount);
        emit WithdrawSafeHavenAsset(
            msg.sender,
            receiver,
            owner,
            safeHavenAssetAmount,
            shares
        );

        return safeHavenAssetAmount;
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public returns (uint256) {
        uint256 assets = convertToAssets(shares);

        _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);

        ERC20(asset).safeTransfer(receiver, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        return assets;
    }

    function redeem(uint256 shares, address receiver)
        external
        returns (uint256)
    {
        return redeem(shares, receiver, msg.sender);
    }

    function redeem(uint256 shares) external returns (uint256) {
        return redeem(shares, msg.sender, msg.sender);
    }

    /// @notice Keeper check
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (
            bool upkeepNeeded,
            bytes memory /* performData */
        )
    {
        (bool shouldLiquidate, ) = isLiquidatable();
        return (
            shouldLiquidate && vaultState != VaultStatus.Liquidatable,
            bytes("")
        );
    }

    /// @notice Keeper job to trigger liquidation mode when liquidatable params are met,
    ///  and to record the closest block number at which it happened.
    function performUpkeep(
        bytes calldata /* performData */
    ) external override {
        (bool shouldLiquidate, uint256 meanPrice) = isLiquidatable();
        require(
            shouldLiquidate && vaultState != VaultStatus.Liquidatable,
            "No upkeep needed"
        );
        vaultState = VaultStatus.Liquidatable;
        vaultLiquidatableAt = block.number;
        emit VaultLiquidatableTriggered(
            block.number,
            block.timestamp,
            meanPrice
        );
    }

    /// @notice Fetch the cumulative price of the last `nOracleRounds` from the oracle.
    /// @return cumulative price
    function getAssetPriceCumulative() private view returns (uint256) {
        (uint80 roundId, int256 price, , uint256 updatedAt, ) = feed
            .latestRoundData();
        require(updatedAt >= block.timestamp - 60, "Price feed stale");
        uint256 cumulativePrice = uint256(price);
        for (uint80 i = roundId - 1; i > roundId - nOracleRounds; --i) {
            uint80 rid = i;
            (, int256 roundPrice, , , ) = feed.getRoundData(rid);
            require(roundPrice > 0, "Invalid round price");
            cumulativePrice += uint256(roundPrice);
        }
        return cumulativePrice;
    }

    /// @notice Fetch instantaneous oracle price of the risky asset.
    function getAssetPrice() private view returns (uint256) {
        (, int256 price, , uint256 updatedAt, ) = feed.latestRoundData();
        require(updatedAt >= block.timestamp - 60, "Price feed stale");
        require(price > 0, "Invalid price from feed");
        return uint256(price);
    }

    /// @notice Returns true if the vault is liquidatable.
    /// @return true if liquidatable, and the mean price
    function isLiquidatable() public view returns (bool, uint256) {
        // Current strategy: liquidatable if mean of latest 5 rounds is lower
        // than the liquidation threshold.
        uint256 assetPriceCumulative = getAssetPriceCumulative();
        bool isAlreadyLiquidatable = vaultState != VaultStatus.Liquidatable;
        bool isBelowLiquidationThreshold = assetPriceCumulative <=
            liquidationThreshold * nOracleRounds;
        return (
            isAlreadyLiquidatable || isBelowLiquidationThreshold,
            assetPriceCumulative / nOracleRounds
        );
    }

    /// @notice Yeet the entire vault into the safe-haven asset (e.g. USDC) at the rate of
    ///  (AT LEAST) the oracle price.
    /// @param safeHavenAssetAmount Amount of safe-haven assets being offered for liquidation
    ///  of this entire vault. This amount of safe-haven assets, minus the reward amount, will be
    ///  taken from the liquidatooor.
    function yeet(uint256 safeHavenAssetAmount) external {
        require(
            vaultState == VaultStatus.Liquidatable,
            "Vault not liquidatable"
        );

        // Ensure liquidation offer is (at least) equivalent to the vault's stop-loss
        uint256 liqOfferPrice = (10**feed.decimals() *
            totalAssets() *
            10**safeHavenAsset.decimals()) /
            (safeHavenAssetAmount * 10**ERC20(asset).decimals());
        require(liqOfferPrice >= stopLoss, "Liquidation offer too low");

        // Effect: vault state is now liquidated
        vaultState = VaultStatus.Liquidated;

        // Take promised amount of safe haven assets from liquidatooooor, minus their reward
        safeHavenAsset.safeTransferFrom(
            msg.sender,
            address(this),
            safeHavenAssetAmount
        );
        // Gib liquidatoooor the rapidly destabilising stablecoin
        ERC20(asset).safeTransfer(msg.sender, totalAssets());
    }
}
