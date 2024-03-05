// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SBPVaultFactory} from "../../../contracts/SBPVaultFactory.sol";
import {ISBPVault} from "../../../contracts/interfaces/ISBPVault.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {ERC20, ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {LpTokenMock} from "../../mocks/LpTokenMock.sol";
import {RouterMock} from "../../mocks/RouterMock.sol";

contract SBPVaultFactoryTest is Test {
    SBPVaultFactory vaultFactory;
    RouterMock router;
    address governor = makeAddr("governor");
    address bob = makeAddr("bob");
    address feeTo = makeAddr("feeTo");
    uint256 initializationAmount = 1 ether;
    uint32 automationInterval = 12 hours;
    ERC20Mock linkToken;
    ERC20Mock mockToken;
    LpTokenMock pairMock;
    uint256 supply = 1000 ether;

    function deployVaultHelper() public returns (address) {
        string memory vaultTokenName = "SelfBalancingMOCKLINK";
        string memory vaultTokenSymbol = "sbpMOCK/LINK";
        vm.startPrank(governor);
        ERC20(pairMock).approve(address(vaultFactory), 1 ether);
        vaultFactory.deployVault(
            address(pairMock),
            governor,
            feeTo,
            false,
            initializationAmount,
            automationInterval,
            vaultTokenName,
            vaultTokenSymbol
        );
        vm.stopPrank();
        return vaultFactory.getVault(address(pairMock));
    }

    function setUp() public {
        linkToken = new ERC20Mock("LINK","LINK", supply);
        mockToken = new ERC20Mock("MOCK","MOCK", supply);
        vm.prank(governor);
        pairMock = new LpTokenMock(address(linkToken), address(mockToken), supply);
        router = new RouterMock(address(linkToken), address(mockToken), address(pairMock));
        linkToken.transfer(address(pairMock), 1 ether);
        mockToken.transfer(address(pairMock), 1 ether);
        vaultFactory = new SBPVaultFactory(governor, address(router));
    }

    function test__SBPVaultFactory_deployVault() public {
        string memory vaultTokenName = "SelfBalancingMOCKLINK";
        string memory vaultTokenSymbol = "sbpMOCK/LINK";
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        vaultFactory.deployVault(
            address(pairMock),
            governor,
            feeTo,
            false,
            initializationAmount,
            automationInterval,
            vaultTokenName,
            vaultTokenSymbol
        );
        vm.startPrank(governor);
        vm.expectRevert("ERC20: insufficient allowance");
        vaultFactory.deployVault(
            address(pairMock),
            governor,
            feeTo,
            false,
            initializationAmount,
            automationInterval,
            vaultTokenName,
            vaultTokenSymbol
        );
        ERC20(pairMock).approve(address(vaultFactory), initializationAmount);
        uint256 balanceBefore = ERC20(pairMock).balanceOf(governor);
        vaultFactory.deployVault(
            address(pairMock),
            governor,
            feeTo,
            false,
            initializationAmount,
            automationInterval,
            vaultTokenName,
            vaultTokenSymbol
        );
        address vaultToken = vaultFactory.getVault(address(pairMock));
        assertTrue(vaultToken != address(0));
        assertTrue(ERC20(vaultToken).balanceOf(governor) == initializationAmount);
        assertTrue(ERC20(pairMock).balanceOf(governor) == balanceBefore - initializationAmount);
        vm.expectRevert(SBPVaultFactory.SBPVaultFactory__VaultAlreadyDeployed.selector);
        vaultFactory.deployVault(
            address(pairMock),
            governor,
            feeTo,
            false,
            initializationAmount,
            automationInterval,
            vaultTokenName,
            vaultTokenSymbol
        );
        vm.stopPrank();
    }

    function test__SBPVaultFactory_setVaultsParams() public {
        uint32 newAutomationInterval = 6 hours;
        address vault = deployVaultHelper();
        (address feeToAddr, bool isFeeOn,, uint32 automationIntervalValue) = ISBPVault(vault).getVaultState();
        assertFalse(feeToAddr == bob);
        assertFalse(isFeeOn);
        assertFalse(automationIntervalValue == newAutomationInterval);
        address[] memory lpTokens = new address[](1);
        lpTokens[0] = address(linkToken);
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        vaultFactory.setVaultsParams(bob, true, newAutomationInterval, lpTokens);
        vm.startPrank(governor);
        vm.expectRevert(SBPVaultFactory.SBPVaultFactory__InvalidVault.selector);
        vaultFactory.setVaultsParams(bob, true, newAutomationInterval, lpTokens);
        lpTokens[0] = address(pairMock);
        vaultFactory.setVaultsParams(bob, true, newAutomationInterval, lpTokens);
        vm.stopPrank();
        (feeToAddr, isFeeOn,, automationIntervalValue) = ISBPVault(vault).getVaultState();
        assertTrue(feeToAddr == bob);
        assertTrue(isFeeOn);
        assertTrue(automationIntervalValue == newAutomationInterval);
    }

    function test__SBPVaultFactory_setVaultsParamsMassive() public {
        uint32 newAutomationInterval = 6 hours;
        address vault = deployVaultHelper();
        (address feeToAddr, bool isFeeOn,, uint32 automationIntervalValue) = ISBPVault(vault).getVaultState();
        assertFalse(feeToAddr == bob);
        assertFalse(isFeeOn);
        assertFalse(automationIntervalValue == newAutomationInterval);
        vm.prank(governor);
        vaultFactory.setVaultsParams(bob, true, newAutomationInterval, new address[](0));
        (feeToAddr, isFeeOn,, automationIntervalValue) = ISBPVault(vault).getVaultState();
        assertTrue(feeToAddr == bob);
        assertTrue(isFeeOn);
        assertTrue(automationIntervalValue == newAutomationInterval);
    }

    function test__SBPVaultFactory_checkUpkeep() public {
        address vault = deployVaultHelper();
        (bool upkeepNeeded, bytes memory performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);
        vm.warp(block.timestamp + 12 hours + 1);
        (upkeepNeeded, performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);
        linkToken.transfer(vault, 1 ether);
        (upkeepNeeded, performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);
        mockToken.transfer(vault, 1 ether);
        (upkeepNeeded, performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertTrue(upkeepNeeded && abi.decode(performData, (address)) == address(pairMock));
    }

    function test__SBPVaultFactory_performUpkeep() public {
        address vault = deployVaultHelper();
        (bool upkeepNeeded, bytes memory performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);
        vm.warp(block.timestamp + 12 hours + 1);
        linkToken.transfer(vault, 1 ether);
        mockToken.transfer(vault, 1 ether);
        vm.prank(governor);
        ERC20(pairMock).transfer(address(router), 1 ether);
        (upkeepNeeded, performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        vaultFactory.performUpkeep(performData);
        assertTrue(ERC20(pairMock).balanceOf(vault) == initializationAmount + router.transferLpAmount());
    }
}
