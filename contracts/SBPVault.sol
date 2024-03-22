// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit, IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISBPVault} from "./interfaces/ISBPVault.sol";
import {IAddLiquidityRouter} from "./interfaces/IAddLiquidityRouter.sol";
import {IPairReserves} from "./interfaces/IPairReserves.sol";

/**
 * @title SBPVault
 * @dev Implements a liquidity vault for self-balancing pools with rewards auto-compounding.
 * @notice This contract allows users to stake liquidity provider (LP) tokens, automatically compound rewards, and withdraw their stakes.
 * @author Oddcod3 (@oddcod3)
 */
contract SBPVault is ISBPVault, ERC20, ERC20Permit("SBPV") {
    using SafeERC20 for IERC20;

    error SBPVault__InitializerTimelock();
    error SBPVault__AlreadyInitialized();
    error SBPVault__InsufficientInitializationAmount();
    error SBPVault__NotVaultFactory();
    error SBPVault__StakingAmountIsZero();
    error SBPVault__ZeroSharesMinted();
    error SBPVault__ZeroSharesBurned();

    /// @dev Fee charged for rebalancing operations plus rewards autocompounding, represented in basis points (parts per 10,000).
    uint256 public constant FEE = 200;
    /// @dev Vault shares time lock period for the initializer, set to 7 days.
    uint256 public constant INITIALIZER_TIMELOCK = 7 days;
    /// @dev Minimum amount of LP tokens required to initialize the vault.
    uint256 public constant MIN_INITIALIZATION_AMOUNT = 1_000_000_000;
    /// @dev Timestamp when the vault was initialized, used in conjunction with `INITIALIZER_TIMELOCK`.
    uint256 private immutable i_initializationTimestamp;
    /// @dev Address of the account that initialized the vault.
    address private immutable i_initializer;
    /// @dev Address of the vault factory that deployed this vault.
    address private immutable i_vaultFactory;
    /// @dev Address of the first token in the LP token pair.
    address private immutable i_token0;
    /// @dev Address of the second token in the LP token pair.
    address private immutable i_token1;
    /// @dev LP token associated with this vault.
    IERC20 private immutable i_lpToken;
    /// @dev Router used for adding liquidity to the liquidity pool.
    IAddLiquidityRouter private immutable i_router;
    /// @dev Current state of the vault, including parameters like the fee recipient, fee switch and automation interval.
    VaultState private s_vaultState;
    /// @dev Boolean flag indicating whether the vault has been initialized.
    bool private s_initialized;

    struct VaultState {
        address feeTo; // Address to which fees are sent
        bool feeOn; // Flag indicating whether fees are currently enabled
        uint48 lastLiquefiedTimestamp; // Timestamp of the last reward liquefaction
        uint32 automationInterval; // Interval for automatic reward liquefaction
    }

    event Staked(address indexed staker, uint256 amount);
    event Withdrawn(address indexed withdrawer, uint256 amount);
    event Liquefied(uint256 balance0, uint256 balance1, uint256 liquidity);
    event VaultStateChanged(address feeTo, bool feeOn, uint32 automationInterval);

    modifier onlyVaultFactory() {
        _revertIfNotFactory();
        _;
    }

    constructor(
        address lpToken,
        address router,
        address initializer,
        address feeTo,
        bool feeOn,
        uint32 automationInterval,
        string memory symbol
    ) ERC20("SBPV", symbol) {
        i_vaultFactory = msg.sender;
        i_lpToken = IERC20(lpToken);
        i_router = IAddLiquidityRouter(router);
        i_initializer = initializer;
        i_initializationTimestamp = block.timestamp;
        IPairReserves pair = IPairReserves(lpToken);
        (address token0, address token1) = (pair.token0(), pair.token1());
        i_token0 = token0;
        i_token1 = token1;
        s_vaultState = VaultState({
            feeTo: feeTo,
            feeOn: feeOn,
            lastLiquefiedTimestamp: uint48(block.timestamp),
            automationInterval: automationInterval
        });
        IERC20(token0).forceApprove(address(router), type(uint256).max);
        IERC20(token1).forceApprove(address(router), type(uint256).max);
    }

    /// @inheritdoc ISBPVault
    function initialize(uint256 initializationAmount) external onlyVaultFactory {
        if (s_initialized) revert SBPVault__AlreadyInitialized();
        uint256 lpTokenBalance = i_lpToken.balanceOf(address(this));
        if (lpTokenBalance < initializationAmount || lpTokenBalance < MIN_INITIALIZATION_AMOUNT) {
            revert SBPVault__InsufficientInitializationAmount();
        }
        s_initialized = true;
        _mint(i_initializer, initializationAmount);
    }

    /// @inheritdoc ISBPVault
    function setVaultParams(address feeTo, bool feeOn, uint32 automationInterval) external onlyVaultFactory {
        VaultState storage vaultState = s_vaultState;
        vaultState.feeTo = feeTo;
        vaultState.feeOn = feeOn;
        vaultState.automationInterval = automationInterval;
        emit VaultStateChanged(feeTo, feeOn, automationInterval);
    }

    /// @inheritdoc ISBPVault
    function stake(uint256 amount) external {
        _onStake(amount);
        i_lpToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc ISBPVault
    function stakeWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        _onStake(amount);
        IERC20Permit(address(i_lpToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        i_lpToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /// @inheritdoc ISBPVault
    function withdraw(uint256 amount) external {
        if (amount == 0) revert SBPVault__ZeroSharesBurned();
        uint256 totalShares = totalSupply();
        _burn(msg.sender, amount);
        i_lpToken.safeTransfer(msg.sender, amount * i_lpToken.balanceOf(address(this)) / totalShares);
        emit Withdrawn(msg.sender, amount);
    }

    /// @inheritdoc ISBPVault
    function exit() external {
        uint256 amountShares = balanceOf(msg.sender);
        uint256 totalShares = totalSupply();
        if (amountShares == 0) revert SBPVault__ZeroSharesBurned();
        _burn(msg.sender, amountShares);
        _liquefyRewards();
        i_lpToken.safeTransfer(msg.sender, amountShares * i_lpToken.balanceOf(address(this)) / totalShares);
        emit Withdrawn(msg.sender, amountShares);
    }

    /// @inheritdoc ISBPVault
    function liquefyRewards() external {
        _liquefyRewards();
    }

    /**
     * @param amount The amount of LP tokens staked.
     */
    function _onStake(uint256 amount) internal {
        if (amount == 0) revert SBPVault__StakingAmountIsZero();
        uint256 amountSharesToMint = amount * totalSupply() / i_lpToken.balanceOf(address(this));
        if (amountSharesToMint == 0) revert SBPVault__ZeroSharesMinted();
        _mint(msg.sender, amountSharesToMint);
        emit Staked(msg.sender, amount);
    }

    /**
     * @dev Internal function to autocompound accumulated rewards into LP tokens.
     * @notice This function updates the last liquidity-added timestamp and adds liquidity using the balances of token0 and token1.
     *         After liquidity is added, if the fee mechanism ('feeOn') is active, a portion of the resulting LP tokens,
     *         calculated based on the defined FEE, is transferred to the fee recipient address stored in the vault's state.
     * @notice Setting minimum amounts for token0 and token1 (amount0Min and amount1Min) when adding liquidity is unnecessary
     *         since self-balancing pools are not open to public trading.
     */
    function _liquefyRewards() internal {
        (uint256 balance0, uint256 balance1) = _getRewardsToLiquefy();
        if (balance0 > 0 && balance1 > 0) {
            VaultState storage vaultState = s_vaultState;
            vaultState.lastLiquefiedTimestamp = uint48(block.timestamp);
            (,, uint256 liquidity) =
                i_router.addLiquidity(i_token0, i_token1, balance0, balance1, 1, 1, address(this), block.timestamp);
            uint256 feeAmount;
            if (vaultState.feeOn) {
                feeAmount = liquidity * FEE / 10_000;
                liquidity = liquidity - feeAmount;
                i_lpToken.safeTransfer(vaultState.feeTo, feeAmount);
            }
            emit Liquefied(balance0, balance1, liquidity);
        }
    }

    /**
     * @dev Internal view function to retrieve the current balances of the two rewards tokens held by the vault.
     * @return balance0 The current balance of the first token (i_token0) held by the vault.
     * @return balance1 The current balance of the second token (i_token1) held by the vault.
     */
    function _getRewardsToLiquefy() internal view returns (uint256 balance0, uint256 balance1) {
        balance0 = IERC20(i_token0).balanceOf(address(this));
        balance1 = IERC20(i_token1).balanceOf(address(this));
    }

    ///@dev Revert if msg.sender is not the vault factory.
    function _revertIfNotFactory() internal view {
        if (msg.sender != i_vaultFactory) revert SBPVault__NotVaultFactory();
    }

    /**
     * @inheritdoc ERC20
     * @dev Hook that is called before any transfer of vault tokens. This includes minting and burning.
     * @param from The address from which the tokens are being transferred.
     * @notice This function checks if the `from` address is the initializer and whether the current timestamp is within the initializer timelock period.
     *         If both conditions are met, the transfer is reverted to prevent the initializer from transferring tokens within the timelock period.
     */
    function _beforeTokenTransfer(address from, address, uint256) internal virtual override {
        if (from == i_initializer && block.timestamp - i_initializationTimestamp < INITIALIZER_TIMELOCK) {
            revert SBPVault__InitializerTimelock();
        }
    }

    /// @inheritdoc ISBPVault
    function isLiquefyNeeded() external view returns (bool) {
        VaultState memory vaultState = s_vaultState;
        (uint256 balance0, uint256 balance1) = _getRewardsToLiquefy();
        return balance0 > 0 && balance1 > 0
            && block.timestamp - vaultState.lastLiquefiedTimestamp > vaultState.automationInterval;
    }

    /// @inheritdoc ISBPVault
    function getVaultState()
        external
        view
        returns (address feeTo, bool feeOn, uint48 lastLiquefiedTimestamp, uint32 automationInterval)
    {
        VaultState memory vaultState = s_vaultState;
        feeTo = vaultState.feeTo;
        feeOn = vaultState.feeOn;
        lastLiquefiedTimestamp = vaultState.lastLiquefiedTimestamp;
        automationInterval = vaultState.automationInterval;
    }

    /// @inheritdoc ISBPVault
    function getRewardTokensBalance() external view returns (address, address, uint256, uint256) {
        (uint256 balance0, uint256 balance1) = _getRewardsToLiquefy();
        return (i_token0, i_token1, balance0, balance1);
    }

    /// @inheritdoc ISBPVault
    function getLpToken() external view returns (address) {
        return address(i_lpToken);
    }

    /// @inheritdoc ISBPVault
    function getInitializationTimestamp() external view returns (uint256) {
        return i_initializationTimestamp;
    }
}
