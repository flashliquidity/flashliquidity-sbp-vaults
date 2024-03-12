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
    SBPVault public vault;
    RouterMock public router;
    ERC20Mock public linkToken;
    ERC20Mock public mockToken;
    LpTokenMock public pairMock;
    address public governor = makeAddr("governor");
    address public bob = makeAddr("bob");
    address public feeTo = makeAddr("feeTo");
    address public vaultFactory = makeAddr("vaultFactory");
    address public initializer = makeAddr("initializer");
    uint256 public initializationAmount = 1_000_000_000;
    uint32 public automationInterval = 12 hours;
    string public vaultName = "SelfBalancingMOCKLINK";
    string public vaultSymbol = "sbpMOCK/LINK";

    function initializeVaultHelper() public {
        pairMock.mintTo(address(vault), initializationAmount);
        vm.prank(vaultFactory);
        vault.initialize(initializationAmount);
    }

    function stakingHelper(address staker, uint256 amount) public {
        vm.startPrank(staker);
        pairMock.approve(address(vault), amount);
        vault.stake(amount);
        vm.stopPrank();
    }

    function setUp() public {
        linkToken = new ERC20Mock("LINK", "LINK");
        mockToken = new ERC20Mock("MOCK", "MOCK");
        pairMock = new LpTokenMock(address(linkToken), address(mockToken));
        pairMock.mintTo(bob, 1000 ether);
        router = new RouterMock(address(linkToken), address(mockToken), address(pairMock));
        linkToken.mintTo(address(pairMock), 1 ether);
        mockToken.mintTo(address(pairMock), 1 ether);
        vm.prank(vaultFactory);
        vault = new SBPVault(
            address(pairMock), address(router), initializer, feeTo, false, automationInterval, vaultName, vaultSymbol
        );
    }

    function test__SBPVault_initialize() public {
        uint256 insufficientInitializationAmount = 999_999_999;
        vm.expectRevert(SBPVault.SBPVault__NotVaultFactory.selector);
        vault.initialize(insufficientInitializationAmount);
        vm.prank(vaultFactory);
        vm.expectRevert(SBPVault.SBPVault__InsufficientInitializationAmount.selector);
        vault.initialize(insufficientInitializationAmount);
        pairMock.mintTo(address(vault), insufficientInitializationAmount);
        vm.prank(vaultFactory);
        vm.expectRevert(SBPVault.SBPVault__InsufficientInitializationAmount.selector);
        vault.initialize(initializationAmount);
        pairMock.mintTo(address(vault), 1);
        vm.prank(vaultFactory);
        vault.initialize(initializationAmount);
        assertEq(ERC20(vault).balanceOf(initializer), initializationAmount);
        vm.prank(vaultFactory);
        vm.expectRevert(SBPVault.SBPVault__AlreadyInitialized.selector);
        vault.initialize(initializationAmount);
    }

    function test__SBPVault_setVaultParams() public {
        uint32 newAutomationInterval = 6 hours;
        (address feeToAddr, bool feeOnValue,, uint32 automationIntervalValue) = vault.getVaultState();
        assertNotEq(feeToAddr, bob);
        assertFalse(feeOnValue);
        assertNotEq(automationIntervalValue, newAutomationInterval);
        vm.expectRevert(SBPVault.SBPVault__NotVaultFactory.selector);
        vault.setVaultParams(bob, true, newAutomationInterval);
        vm.prank(vaultFactory);
        vault.setVaultParams(bob, true, newAutomationInterval);
        (feeToAddr, feeOnValue,, automationIntervalValue) = vault.getVaultState();
        assertEq(feeToAddr, bob);
        assertTrue(feeOnValue);
        assertEq(automationIntervalValue, newAutomationInterval);
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
        pairMock.approve(address(vault), stakingAmount);
        vault.stake(stakingAmount);
        vm.stopPrank();
        assertEq(vault.balanceOf(bob), 1 ether);
    }

    function test__SBPVault_withdraw() public {
        initializeVaultHelper();
        vm.expectRevert("ERC20: burn amount exceeds balance");
        vault.withdraw(1 ether);
        stakingHelper(bob, 1 ether);
        uint256 bobLpBalanceBeforeWithdraw = pairMock.balanceOf(bob);
        uint256 vaultTokenSupplyBeforeWithdraw = vault.totalSupply();
        vm.prank(bob);
        vault.withdraw(1 ether);
        uint256 bobLpBalanceAfterWithdraw = pairMock.balanceOf(bob);
        uint256 vaultTokenSupplyAfterWithdraw = vault.totalSupply();
        assertEq(bobLpBalanceAfterWithdraw, bobLpBalanceBeforeWithdraw + 1 ether);
        assertEq(vaultTokenSupplyAfterWithdraw, vaultTokenSupplyBeforeWithdraw - 1 ether);
    }

    function test__SBPVault_exitNoAutocompound() public {
        initializeVaultHelper();
        vm.expectRevert(SBPVault.SBPVault__ZeroSharesBurned.selector);
        vault.exit();
        stakingHelper(bob, 1 ether);
        uint256 bobLpBalanceBeforeWithdraw = pairMock.balanceOf(bob);
        uint256 vaultTokenSupplyBeforeWithdraw = vault.totalSupply();
        vm.prank(bob);
        vault.exit();
        uint256 bobLpBalanceAfterWithdraw = pairMock.balanceOf(bob);
        uint256 vaultTokenSupplyAfterWithdraw = vault.totalSupply();
        assertEq(bobLpBalanceAfterWithdraw, bobLpBalanceBeforeWithdraw + 1 ether);
        assertEq(vaultTokenSupplyAfterWithdraw, vaultTokenSupplyBeforeWithdraw - 1 ether);
    }

    function test__SBPVault_exitAndAutocompound() public {
        initializeVaultHelper();
        vm.expectRevert(SBPVault.SBPVault__ZeroSharesBurned.selector);
        vault.exit();
        stakingHelper(bob, 1 ether);
        uint256 bobLpBalanceBeforeWithdraw = pairMock.balanceOf(bob);
        uint256 vaultTokenSupplyBeforeWithdraw = vault.totalSupply();
        linkToken.mintTo(address(vault), 1 ether);
        mockToken.mintTo(address(vault), 1 ether);
        vm.prank(bob);
        vault.exit();
        uint256 bobLpBalanceAfterWithdraw = pairMock.balanceOf(bob);
        uint256 vaultTokenSupplyAfterWithdraw = vault.totalSupply();
        assertGt(bobLpBalanceAfterWithdraw, bobLpBalanceBeforeWithdraw + 1 ether);
        assertEq(vaultTokenSupplyAfterWithdraw, vaultTokenSupplyBeforeWithdraw - 1 ether);
    }
}
