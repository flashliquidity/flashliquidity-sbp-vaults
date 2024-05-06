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
    SBPVaultFactory public vaultFactory;
    RouterMock public router;
    ERC20Mock public linkToken;
    ERC20Mock public mockToken;
    LpTokenMock public pairMock;
    address public governor = makeAddr("governor");
    address public bob = makeAddr("bob");
    address public feeTo = makeAddr("feeTo");
    uint256 public initAmount = 1 ether;
    uint32 public automationInterval = 12 hours;
    uint16 public fee = 200;
    string public vaultSymbol = "SBPV-MOCK/LINK";

    function deployVaultHelper() public returns (address) {
        vm.startPrank(governor);
        pairMock.approve(address(vaultFactory), 1 ether);
        vaultFactory.deployVault(
            address(pairMock), governor, initAmount, feeTo, false, fee, automationInterval, vaultSymbol
        );
        vm.stopPrank();
        return vaultFactory.getVault(address(pairMock));
    }

    function setUp() public {
        linkToken = new ERC20Mock("LINK", "LINK");
        mockToken = new ERC20Mock("MOCK", "MOCK");
        pairMock = new LpTokenMock(address(linkToken), address(mockToken));
        pairMock.mintTo(governor, 1000 ether);
        router = new RouterMock(address(linkToken), address(mockToken), address(pairMock));
        linkToken.mintTo(address(pairMock), 1 ether);
        mockToken.mintTo(address(pairMock), 1 ether);
        vaultFactory = new SBPVaultFactory(governor, address(router));
    }

    function test__SBPVaultFactory_deployVault() public {
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        vaultFactory.deployVault(
            address(pairMock), governor, initAmount, feeTo, false, fee, automationInterval, vaultSymbol
        );
        vm.startPrank(governor);
        vm.expectRevert("ERC20: insufficient allowance");
        vaultFactory.deployVault(
            address(pairMock), governor, initAmount, feeTo, false, fee, automationInterval, vaultSymbol
        );
        pairMock.approve(address(vaultFactory), initAmount);
        uint256 balanceBefore = pairMock.balanceOf(governor);
        vaultFactory.deployVault(
            address(pairMock), governor, initAmount, feeTo, false, fee, automationInterval, vaultSymbol
        );
        address vaultToken = vaultFactory.getVault(address(pairMock));
        assertNotEq(vaultToken, address(0));
        assertEq(ERC20(vaultToken).balanceOf(governor), initAmount);
        assertEq(pairMock.balanceOf(governor), balanceBefore - initAmount);
        vm.expectRevert(SBPVaultFactory.SBPVaultFactory__VaultAlreadyDeployed.selector);
        vaultFactory.deployVault(
            address(pairMock), governor, initAmount, feeTo, false, fee, automationInterval, vaultSymbol
        );
        vm.stopPrank();
    }

    function test__SBPVaultFactory_setVaultsParams() public {
        uint32 newAutomationInterval = 6 hours;
        uint16 newFeeValue = 500;
        address vault = deployVaultHelper();
        ISBPVault.VaultState memory vaultState = ISBPVault(vault).getVaultState();
        assertNotEq(vaultState.feeTo, bob);
        assertFalse(vaultState.feeOn);
        assertNotEq(vaultState.fee, newFeeValue);
        assertNotEq(vaultState.automationInterval, newAutomationInterval);
        address[] memory vaults = new address[](1);
        address[] memory feesTo = new address[](1);
        bool[] memory feesOn = new bool[](1);
        uint16[] memory fees = new uint16[](1);
        uint32[] memory automationIntervals = new uint32[](1);
        vaults[0] = vault;
        feesTo[0] = bob;
        feesOn[0] = true;
        fees[0] = newFeeValue;
        automationIntervals[0] = newAutomationInterval;
        vm.expectRevert(Governable.Governable__NotAuthorized.selector);
        vaultFactory.setVaultsParams(vaults, feesTo, feesOn, fees, automationIntervals);
        vm.startPrank(governor);
        vaultFactory.setVaultsParams(vaults, feesTo, feesOn, fees, automationIntervals);
        vm.stopPrank();
        vaultState = ISBPVault(vault).getVaultState();
        assertEq(vaultState.feeTo, bob);
        assertTrue(vaultState.feeOn);
        assertEq(vaultState.fee, newFeeValue);
        assertEq(vaultState.automationInterval, newAutomationInterval);
    }

    function test__SBPVaultFactory_checkUpkeep() public {
        address vault = deployVaultHelper();
        (bool upkeepNeeded, bytes memory performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);
        vm.warp(block.timestamp + 12 hours + 1);
        (upkeepNeeded, performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);
        linkToken.mintTo(vault, 1 ether);
        (upkeepNeeded, performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);
        mockToken.mintTo(vault, 1 ether);
        (upkeepNeeded, performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertTrue(upkeepNeeded);
        assertEq(abi.decode(performData, (address)), address(pairMock));
    }

    function test__SBPVaultFactory_performUpkeep() public {
        address vault = deployVaultHelper();
        (bool upkeepNeeded, bytes memory performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        assertFalse(upkeepNeeded);
        vm.warp(block.timestamp + 12 hours + 1);
        linkToken.mintTo(vault, 1 ether);
        mockToken.mintTo(vault, 1 ether);
        vm.prank(governor);
        pairMock.transfer(address(router), 1 ether);
        (upkeepNeeded, performData) = vaultFactory.checkUpkeep(abi.encode(0, 10));
        vaultFactory.performUpkeep(performData);
        assertEq(pairMock.balanceOf(vault), initAmount + router.transferLpAmount());
    }
}
