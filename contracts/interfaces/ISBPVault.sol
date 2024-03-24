// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISBPVault {
    /**
     * @dev Initializes the vault with a specified amount of LP tokens.
     * @param initializationAmount The amount of LP tokens to initialize the vault with.
     * @notice This function can only be called once and only by the vault factory contract.
     *         This function will revert if called after the vault has already been initialized or if the contract does not have enough LP tokens to meet the requested amount.
     */
    function initialize(uint256 initializationAmount) external;

    /**
     * @dev Sets various parameters of the vault, including fee recipient, fee status, and automation interval.
     * @param feeTo The address to which fees generated by the vault are sent.
     * @param feeOn A boolean indicating whether the fee mechanism is active.
     * @param automationInterval The time interval in seconds for automatic reward compounding.
     * @notice This function can only be called by the factory contract.
     */
    function setVaultParams(address feeTo, bool feeOn, uint32 automationInterval) external;

    /**
     * @dev Allows a user to stake LP tokens in the vault.
     * @param amount The amount of LP tokens the user wishes to stake.
     */
    function stake(uint256 amount) external;

    /**
     * @dev Allows a user to stake LP tokens in the vault using the permit function.
     *      This method enables users to approve and stake tokens in a single transaction,
     *      bypassing the need for a separate approval transaction.
     * @param amount The amount of LP tokens the user wishes to stake.
     * @param deadline The timestamp until which the permit is valid. The transaction must be mined before this time.
     * @param v The recovery byte of the signature; a part of the EIP-712 signature standard.
     * @param r Half of the ECDSA signature pair; a part of the EIP-712 signature standard.
     * @param s Half of the ECDSA signature pair; a part of the EIP-712 signature standard.
     */
    function stakeWithPermit(uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @dev Allows a user to withdraw their staked LP tokens and any accrued rewards from the vault.
     * @param amount The number of vault shares the user wishes to withdraw.
     */
    function withdraw(uint256 amount) external;

    /**
     * @dev Burns the user's entire balance of vault shares and withdraws staked LP tokens along with any rewards.
     * @notice This function also automatically compounds any rewards deposited in the vault.
     */
    function exit() external;

    /// @dev Autocompound rewards deposited into the vault in LP tokens.
    function liquefyRewards() external;

    /**
     * @dev Returns a boolean indicating whether rewards need to be autocompunded based on current vault conditions.
     * @return isNeeded Indicates if autocompounding rewards is necessary.
     */
    function isLiquefyNeeded() external view returns (bool isNeeded);

    /**
     * @dev Retrieves the current state of the vault, including fee recipient, fee status, last liquefied timestamp, and automation interval.
     * @return feeTo Address where fees are sent.
     * @return feeOn Boolean indicating whether the fee mechanism is currently active.
     * @return lastLiquefiedTimestamp Timestamp of the last reward liquefaction.
     * @return automationInterval Interval, in seconds, for automatic compounding of rewards.
     */
    function getVaultState()
        external
        view
        returns (address feeTo, bool feeOn, uint48 lastLiquefiedTimestamp, uint32 automationInterval);

    /**
     * @dev Calculates the rate of vault shares to LP tokens.
     * This function provides the conversion rate from the amount of vault shares 
     * to the equivalent amount in LP tokens based on the current balance and total supply.
     * @param amountShares The amount of vault shares to be converted.
     * @return rate The calculated rate of vault shares to LP tokens.
     */
    function getVaultSharesToLpToken(uint256 amountShares) external view returns (uint256 rate);

    /**
     * @dev Returns the current balances of the reward tokens held by the contract.
     * @return token0 The address of the first reward token.
     * @return token1 The address of the second reward token.
     * @return balance0 The current balance of the first reward token in the contract.
     * @return balance1 The current balance of the second reward token in the contract.
     */
    function getRewardTokensBalance()
        external
        view
        returns (address token0, address token1, uint256 balance0, uint256 balance1);

    /**
     * @dev Returns the address of the LP token associated with the vault.
     * @return address Address of the LP token.
     */
    function getLpToken() external view returns (address);

    /**
     * @dev Returns the timestamp when the vault was initialized.
     * @return uint256 The initialization timestamp.
     */
    function getInitializationTimestamp() external view returns (uint256);
}
