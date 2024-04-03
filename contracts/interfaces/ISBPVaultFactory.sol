// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISBPVaultFactory {
    /**
     * @dev This function is used to batch update parameters for multiple vaults.
     * @param vaults Array of vault addresses to be updated.
     * @param feesTo Array of addresses to which generated fees will be sent.
     * @param feesOn Array of boolean flags to enable or disable fee collection.
     * @param fees Array of new fee values.
     * @param automationIntervals Array of new intervals for automatic reward compounding.
     * @dev Only callable by the governor of the contract. It updates the fee recipient, fee toggle, fee value, and automation interval for selected vaults.
     */
    function setVaultsParams(
        address[] calldata vaults,
        address[] calldata feesTo,
        bool[] calldata feesOn,
        uint16[] calldata fees,
        uint32[] calldata automationIntervals
    ) external;

    /**
     * @dev Deploys a new vault for the specified LP token.
     * @param lpToken The address of the LP token for which the vault is being deployed.
     * @param initializer The address initializing the vault, usually providing initial liquidity.
     * @param initializationAmount The amount of LP tokens to be transferred to the vault upon initialization.
     * @param feeTo The address where fees from the vault will be sent.
     * @param feeOn A boolean indicating whether the fee mechanism is active.
     * @param fee The fee value represented in basis points.
     * @param automationInterval The minimum interval in seconds between rewards autocompounding (liquefyRewards) via Chainlink Automation.
     * @param symbol The symbol for the new vault.
     * @notice This function will revert with 'SBPFarmFactory__AlreadyDeployed' if a vault for the specified LP token already exists.
     */
    function deployVault(
        address lpToken,
        address initializer,
        uint256 initializationAmount,
        address feeTo,
        bool feeOn,
        uint16 fee,
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
