// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SBPVault} from "../../../contracts/SBPVault.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {ERC20, ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {LpTokenMock} from "../../mocks/LpTokenMock.sol";
import {RouterMock} from "../../mocks/RouterMock.sol";

contract SBPVaultTest is Test {
    SBPVault vault;
    RouterMock router;
    address governor = makeAddr("governor");
    address bob = makeAddr("bob");
    address feeTo = makeAddr("feeTo");
    address vaultFactory = makeAddr("vaultFactory");
    address initializer = makeAddr("initializer");
    uint256 initializationAmount = 1_000_000_000;
    uint32 automationInterval = 12 hours;
    ERC20Mock linkToken;
    ERC20Mock mockToken;
    LpTokenMock pairMock;
    uint256 supply = 1000 ether;

    function initializeVaultHelper() public {
        vm.prank(bob);
        ERC20(pairMock).transfer(address(vault), initializationAmount);
        vm.prank(vaultFactory);
        vault.initialize(initializationAmount);
    }

    function stakingHelper(address staker, uint256 amount) public {
        vm.startPrank(staker);
        ERC20(pairMock).approve(address(vault), amount);
        vault.stake(amount);
        vm.stopPrank();
    }

    function setUp() public {
        linkToken = new ERC20Mock("LINK","LINK", supply);
        mockToken = new ERC20Mock("MOCK","MOCK", supply);
        vm.prank(bob);
        pairMock = new LpTokenMock(address(linkToken), address(mockToken), supply);
        router = new RouterMock(address(linkToken), address(mockToken), address(pairMock));
        vm.prank(bob);
        ERC20(pairMock).transfer(address(router), 5 ether);
        linkToken.transfer(address(pairMock), 1 ether);
        mockToken.transfer(address(pairMock), 1 ether);
        string memory vaultTokenName = "SelfBalancingMOCKLINK";
        string memory vaultTokenSymbol = "sbpMOCK/LINK";
        vm.prank(vaultFactory);
        vault =
        new SBPVault(address(pairMock), address(router), initializer, feeTo, false, automationInterval, vaultTokenName, vaultTokenSymbol);
    }

    function test__SBPVault_initialize() public {
        uint256 insufficientInitializationAmount = 999_999_999;
        vm.expectRevert(SBPVault.SBPVault__NotVaultFactory.selector);
        vault.initialize(insufficientInitializationAmount);
        vm.prank(vaultFactory);
        vm.expectRevert(SBPVault.SBPVault__InsufficientInitializationAmount.selector);
        vault.initialize(insufficientInitializationAmount);
        vm.prank(bob);
        ERC20(pairMock).transfer(address(vault), insufficientInitializationAmount);
        vm.prank(vaultFactory);
        vm.expectRevert(SBPVault.SBPVault__InsufficientInitializationAmount.selector);
        vault.initialize(insufficientInitializationAmount);
        vm.prank(bob);
        ERC20(pairMock).transfer(address(vault), 1);
        vm.prank(vaultFactory);
        vault.initialize(initializationAmount);
        assertTrue(ERC20(vault).balanceOf(initializer) == initializationAmount);
        vm.prank(vaultFactory);
        vm.expectRevert(SBPVault.SBPVault__AlreadyInitialized.selector);
        vault.initialize(initializationAmount);
    }

    function test__SBPVault_setVaultParams() public {
        uint32 newAutomationInterval = 6 hours;
        (address feeToAddr, bool feeOnValue,, uint32 automationIntervalValue) = vault.getVaultState();
        assertFalse(feeToAddr == bob);
        assertFalse(feeOnValue);
        assertFalse(automationIntervalValue == newAutomationInterval);
        vm.expectRevert(SBPVault.SBPVault__NotVaultFactory.selector);
        vault.setVaultParams(bob, true, newAutomationInterval);
        vm.prank(vaultFactory);
        vault.setVaultParams(bob, true, newAutomationInterval);
        (feeToAddr, feeOnValue,, automationIntervalValue) = vault.getVaultState();
        assertTrue(feeToAddr == bob);
        assertTrue(feeOnValue);
        assertTrue(automationIntervalValue == newAutomationInterval);
    }

    function test__SBPVault_stake() public {
        initializeVaultHelper();
        uint256 stakingAmount = 1 ether;
        vm.expectRevert(SBPVault.SBPVault__StakingAmountIsZero.selector);
        vault.stake(0);
        vm.prank(bob);
        vm.expectRevert("ERC20: insufficient allowance");
        vault.stake(stakingAmount);
        vm.startPrank(bob);
        ERC20(pairMock).approve(address(vault), stakingAmount);
        vault.stake(stakingAmount);
        vm.stopPrank();
        assertTrue(ERC20(vault).balanceOf(bob) == 1 ether);
    }

    function test__SBPVault_withdraw() public {
        initializeVaultHelper();
        vm.expectRevert("ERC20: burn amount exceeds balance");
        vault.withdraw(1 ether);
        stakingHelper(bob, 1 ether);
        uint256 bobLpBalanceBeforeWithdraw = ERC20(pairMock).balanceOf(bob);
        uint256 vaultTokenSupplyBeforeWithdraw = ERC20(vault).totalSupply();
        vm.prank(bob);
        vault.withdraw(1 ether);
        uint256 bobLpBalanceAfterWithdraw = ERC20(pairMock).balanceOf(bob);
        uint256 vaultTokenSupplyAfterWithdraw = ERC20(vault).totalSupply();
        assertTrue(bobLpBalanceAfterWithdraw == bobLpBalanceBeforeWithdraw + 1 ether);
        assertTrue(vaultTokenSupplyAfterWithdraw == vaultTokenSupplyBeforeWithdraw - 1 ether);
    }

    function test__SBPVault_exitNoAutocompound() public {
        initializeVaultHelper();
        vm.expectRevert(SBPVault.SBPVault__ZeroSharesBurned.selector);
        vault.exit();
        stakingHelper(bob, 1 ether);
        uint256 bobLpBalanceBeforeWithdraw = ERC20(pairMock).balanceOf(bob);
        uint256 vaultTokenSupplyBeforeWithdraw = ERC20(vault).totalSupply();
        vm.prank(bob);
        vault.exit();
        uint256 bobLpBalanceAfterWithdraw = ERC20(pairMock).balanceOf(bob);
        uint256 vaultTokenSupplyAfterWithdraw = ERC20(vault).totalSupply();
        assertTrue(bobLpBalanceAfterWithdraw == bobLpBalanceBeforeWithdraw + 1 ether);
        assertTrue(vaultTokenSupplyAfterWithdraw == vaultTokenSupplyBeforeWithdraw - 1 ether);
    }

    function test__SBPVault_exitAndAutocompound() public {
        initializeVaultHelper();
        vm.expectRevert(SBPVault.SBPVault__ZeroSharesBurned.selector);
        vault.exit();
        stakingHelper(bob, 1 ether);
        uint256 bobLpBalanceBeforeWithdraw = ERC20(pairMock).balanceOf(bob);
        uint256 vaultTokenSupplyBeforeWithdraw = ERC20(vault).totalSupply();
        linkToken.transfer(address(vault), 1 ether);
        mockToken.transfer(address(vault), 1 ether);
        vm.prank(bob);
        vault.exit();
        uint256 bobLpBalanceAfterWithdraw = ERC20(pairMock).balanceOf(bob);
        uint256 vaultTokenSupplyAfterWithdraw = ERC20(vault).totalSupply();
        assertTrue(bobLpBalanceAfterWithdraw > bobLpBalanceBeforeWithdraw + 1 ether);
        assertTrue(vaultTokenSupplyAfterWithdraw == vaultTokenSupplyBeforeWithdraw - 1 ether);
    }
}
