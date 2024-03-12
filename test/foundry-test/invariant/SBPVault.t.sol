// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SBPVault} from "../../../contracts/SBPVault.sol";
import {Governable} from "flashliquidity-acs/contracts/Governable.sol";
import {ERC20, ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {LpTokenMock} from "../../mocks/LpTokenMock.sol";
import {RouterMock} from "../../mocks/RouterMock.sol";
import {VaultHandler} from "../handlers/VaultHandler.sol";
import "forge-std/console.sol";

contract SBPVaultInvariantTest is Test {
    SBPVault public vault;
    VaultHandler public handler;
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

    function setUp() public {
        linkToken = new ERC20Mock("LINK", "LINK");
        mockToken = new ERC20Mock("MOCK", "MOCK");
        pairMock = new LpTokenMock(address(linkToken), address(mockToken));
        router = new RouterMock(address(linkToken), address(mockToken), address(pairMock));
        vm.prank(vaultFactory);
        vault = new SBPVault(
            address(pairMock), address(router), initializer, feeTo, true, automationInterval, vaultName, vaultSymbol
        );
        pairMock.mintTo(address(vault), initializationAmount);
        vm.prank(vaultFactory);
        vault.initialize(initializationAmount);
        handler = new VaultHandler(vault, pairMock);
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = VaultHandler.stake.selector;
        selectors[1] = VaultHandler.withdraw.selector;
        selectors[2] = VaultHandler.exit.selector;
        selectors[3] = VaultHandler.liquefyRewards.selector;
        selectors[4] = VaultHandler.sendRewardsToVault.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    // coverage skip workaround
    function test() public {}

    function invariant_SBPVault_VaultSharesLteLpTokenDeposit() public {
        if (handler.counterRewardsLiquefied() > 0) {
            assertTrue(vault.totalSupply() < pairMock.balanceOf(address(vault)));
        } else {
            assertTrue(vault.totalSupply() == pairMock.balanceOf(address(vault)));
        }
    }

    function invariant_SBPVault_FeesCollection() public {
        assertTrue(
            pairMock.balanceOf(feeTo) == router.transferLpAmount() * handler.counterRewardsLiquefied() * 200 / 10_000
        );
    }
}
