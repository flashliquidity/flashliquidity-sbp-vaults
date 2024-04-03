//SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {AutomationCompatibleInterface} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {ISBPVaultFactory} from "./interfaces/ISBPVaultFactory.sol";
import {ISBPVault, SBPVault} from "./SBPVault.sol";

/**
 * @title SBPVaultFactory
 * @dev Manages and deploys SBP Vaults for self-balancing pools, enabling parameter configuration and rewards auto-compouding operations.
 * @author Oddcod3
 */
contract SBPVaultFactory is ISBPVaultFactory, AutomationCompatibleInterface, Governable {
    using SafeERC20 for IERC20;

    error SBPVaultFactory__InvalidVault();
    error SBPVaultFactory__VaultAlreadyDeployed();
    error SBPVaultFactory__InconsistentParamsLength();

    /// @dev The address of the router used for interacting with liquidity pools.
    address private immutable i_router;
    /// @dev An array storing the addresses of all LP tokens managed by the contract.
    address[] private s_lpTokens;
    /// @dev A mapping from LP token addresses to their corresponding vault addresses.
    mapping(address => address) private s_lpTokenVault;

    event VaultDeployed(address indexed lpToken, address indexed vault);

    constructor(address governor, address router) Governable(governor) {
        i_router = router;
    }

    /// @inheritdoc ISBPVaultFactory
    function setVaultsParams(
        address[] calldata vaults,
        address[] calldata feesTo,
        bool[] calldata feesOn,
        uint16[] calldata fees,
        uint32[] calldata automationIntervals
    ) external onlyGovernor {
        uint256 vaultsLen = vaults.length;
        if (
            vaultsLen != feesTo.length || vaultsLen != feesOn.length || vaultsLen != fees.length
                || vaultsLen != automationIntervals.length
        ) {
            revert SBPVaultFactory__InconsistentParamsLength();
        }
        for (uint256 i; i < vaultsLen;) {
            ISBPVault(vaults[i]).setVaultParams(feesTo[i], feesOn[i], fees[i], automationIntervals[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc ISBPVaultFactory
    function deployVault(
        address lpToken,
        address initializer,
        uint256 initializationAmount,
        address feeTo,
        bool feeOn,
        uint16 fee,
        uint32 automationInterval,
        string memory symbol
    ) external onlyGovernor {
        if (s_lpTokenVault[lpToken] != address(0)) revert SBPVaultFactory__VaultAlreadyDeployed();
        s_lpTokens.push(lpToken);
        address vault =
            address(new SBPVault(i_router, lpToken, initializer, feeTo, feeOn, fee, automationInterval, symbol));
        s_lpTokenVault[lpToken] = vault;
        IERC20(lpToken).safeTransferFrom(initializer, vault, initializationAmount);
        ISBPVault(vault).initialize(initializationAmount);
        emit VaultDeployed(lpToken, vault);
    }

    /**
     * @inheritdoc AutomationCompatibleInterface
     * @dev This function decodes the `performData` to get the address of the vault and then triggers the `liquefyRewards` function on that vault.
     * @param performData Encoded data containing the address of the LP token vault for which upkeep is to be performed.
     */
    function performUpkeep(bytes calldata performData) external override {
        address vault = s_lpTokenVault[abi.decode(performData, (address))];
        if (vault == address(0)) revert SBPVaultFactory__InvalidVault();
        ISBPVault(vault).liquefyRewards();
    }

    /**
     * @inheritdoc AutomationCompatibleInterface
     * @dev Checks if any vault within a specified range needs upkeep (e.g., for reward autocompounding).
     *      This contract integrates with Chainlink Automation, implementing the AutomationCompatibleInterface.
     * @param checkData Encoded data specifying the range of vaults to check, as start and end indices in the 's_lpTokens' array.
     * @return bool A boolean value indicating whether any vault within the specified range requires upkeep.
     * @return bytes Encoded data containing the LP token address of the vault that needs upkeep. Returns an empty byte array if no upkeep is needed.
     * @notice The function decodes `checkData` to obtain the range (start and end indices). It then iterates over the specified range of LP tokens.
     *         For each LP token, it checks if the corresponding vault needs upkeep. If so, it returns true and encodes the LP token address.
     */
    function checkUpkeep(bytes calldata checkData) external view override returns (bool, bytes memory) {
        (uint256 startIndex, uint256 endIndex) = abi.decode(checkData, (uint256, uint256));
        if (endIndex > s_lpTokens.length) {
            endIndex = s_lpTokens.length;
        }
        ISBPVault vault;
        for (uint256 i = startIndex; i < endIndex;) {
            vault = ISBPVault(s_lpTokenVault[s_lpTokens[i]]);
            if (vault.isLiquefyNeeded()) return (true, abi.encode(s_lpTokens[i]));
            unchecked {
                ++i;
            }
        }
        return (false, new bytes(0));
    }

    /// @inheritdoc ISBPVaultFactory
    function getLpTokenAtIndex(uint256 lpTokenIndex) external view returns (address) {
        return s_lpTokens[lpTokenIndex];
    }

    /// @inheritdoc ISBPVaultFactory
    function allLpTokensLength() external view returns (uint256) {
        return s_lpTokens.length;
    }

    /// @inheritdoc ISBPVaultFactory
    function getVault(address lpToken) external view returns (address) {
        return s_lpTokenVault[lpToken];
    }
}
