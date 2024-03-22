// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISBPVaultFactory {
    /**
     * @dev This function is used to batch update parameters for multiple vaults.
     * @param feeTo Address to which generated fees will be sent.
     * @param feeOn Boolean flag to enable or disable fee collection.
     * @param automationInterval Interval in seconds for automatic reward compounding.
     * @param lpTokens Array of LP token addresses for which the vault parameters are to be updated. If empty, updates all vaults.
     * @dev Only callable by the governor of the contract. It updates the fee recipient, fee toggle, and automation interval for selected or all vaults.
     */
    function setVaultsParams(address feeTo, bool feeOn, uint32 automationInterval, address[] memory lpTokens)
        external;

    /**
     * @dev Deploys a new vault for the specified LP token.
     * @param lpToken The address of the LP token for which the vault is being deployed.
     * @param feeTo The address where fees from the vault will be sent.
     * @param initializer The address initializing the vault, usually providing initial liquidity.
     * @param feeOn A boolean indicating whether the fee mechanism is active.yarn
     * @param initializationAmount The amount of LP tokens to be transferred to the vault upon initialization.
     * @param automationInterval The minimum interval in seconds between rewards autocompounding (liquefyRewards) via Chainlink Automation.
     * @param symbol The symbol for the new vault.
     * @notice This function will revert with 'SBPFarmFactory__AlreadyDeployed' if a vault for the specified LP token already exists.
     */
    function deployVault(
        address lpToken,
        address feeTo,
        address initializer,
        bool feeOn,
        uint256 initializationAmount,
        uint32 automationInterval,
        string memory symbol
    ) external;

    /**
     * @notice Retrieves the address of the LP token stored at a specific index.
     * @param lpTokenIndex The index of the LP token in the array.
     * @return lpToken The address of the LP token at the specified index.
     */
    function getLpTokenAtIndex(uint256 lpTokenIndex) external view returns (address lpToken);

    /**
     * @notice Returns the total number of LP tokens managed by the contract.
     * @return lpTokensLength The total number of LP tokens in the contract's storage.
     */
    function allLpTokensLength() external view returns (uint256 lpTokensLength);

    /**
     * @notice Retrieves the address of the vault associated with a specific LP token.
     * @param lpToken The address of the LP token for which the vault address is requested.
     * @return vault The address of the vault associated with the specified LP token.
     */
    function getVault(address lpToken) external view returns (address vault);
}
