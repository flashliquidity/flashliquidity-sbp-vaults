// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SBPVault} from "../../../contracts/SBPVault.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {ERC20, ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {LpTokenMock} from "../../mocks/LpTokenMock.sol";
import {RouterMock} from "../../mocks/RouterMock.sol";

contract SBPVaultInvariantTest is Test {
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
        vm.prank(bob);
        ERC20(pairMock).transfer(address(vault), initializationAmount);
        vm.prank(vaultFactory);
        vault.initialize(initializationAmount);
    }

    // coverage skip workaround
    function test() public {}

    function invariant_SBPVault_VaultTokenSupplyNeverExceedsLpDeposit() public {
        uint256 amount;
        amount = bound(amount, 0, pairMock.balanceOf(msg.sender));
        if(amount > 0) {
            pairMock.approve(address(vault), amount);
            vault.stake(amount);
        }
        assertTrue(ERC20(vault).totalSupply() <= pairMock.balanceOf(address(vault))); 
    }
}
