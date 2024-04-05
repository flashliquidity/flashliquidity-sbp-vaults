// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {ERC20Mock, LpTokenMock} from "../../mocks/LpTokenMock.sol";
import {SBPVault} from "../../../contracts/SBPVault.sol";

contract VaultHandler is CommonBase, StdCheats, StdUtils {
    SBPVault public vault;
    LpTokenMock public vaultLpToken;
    ERC20Mock public lpToken0;
    ERC20Mock public lpToken1;
    uint256 public counterRewardsLiquefied;
    address[] internal actors;
    address internal currentActor;

    modifier createActor() {
        currentActor = msg.sender;
        actors.push(msg.sender);
        _;
    }

    modifier useActor(uint256 actorIndex) {
        actorIndex = bound(actorIndex, 0, actors.length - 1);
        currentActor = actors[actorIndex];
        _;
    }

    constructor(SBPVault _vault, LpTokenMock _vaultLpToken) {
        vault = _vault;
        vaultLpToken = _vaultLpToken;
        lpToken0 = ERC20Mock(_vaultLpToken.token0());
        lpToken1 = ERC20Mock(_vaultLpToken.token1());
    }

    function stake(uint256 amount) external createActor {
        amount = bound(amount, 0, type(uint256).max - vaultLpToken.totalSupply() - 1);
        _countRewardsLiquefied();
        vm.startPrank(currentActor);
        vaultLpToken.mintTo(currentActor, amount);
        vaultLpToken.approve(address(vault), amount);
        vault.stake(amount);
        vm.stopPrank();
    }

    function withdraw(uint256 actorIndex, uint256 amount) external useActor(actorIndex) {
        amount = bound(amount, 0, vault.balanceOf(currentActor));
        vm.startPrank(currentActor);
        vault.withdraw(amount);
        vm.stopPrank();
    }

    function exit(uint256 actorIndex) external useActor(actorIndex) {
        _countRewardsLiquefied();
        vm.startPrank(currentActor);
        vault.exit();
        vm.stopPrank();
    }

    function liquefyRewards() external {
        _countRewardsLiquefied();
        vault.liquefyRewards();
    }

    function sendRewardsToVault(uint256 amount0, uint256 amount1) external {
        amount0 = bound(amount0, 0, type(uint256).max - lpToken0.totalSupply() - 1);
        amount1 = bound(amount1, 0, type(uint256).max - lpToken1.totalSupply() - 1);
        lpToken0.mintTo(address(vault), amount0);
        lpToken1.mintTo(address(vault), amount1);
    }

    function _countRewardsLiquefied() internal {
        if (lpToken0.balanceOf(address(vault)) > 0 && lpToken1.balanceOf(address(vault)) > 0) {
            counterRewardsLiquefied += 1;
        }
    }
}
