// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAddLiquidityRouter} from "../../contracts/interfaces/IAddLiquidityRouter.sol";
import {LpTokenMock} from "./LpTokenMock.sol";

contract RouterMock is IAddLiquidityRouter {

    uint256 public transferLpAmount = 1 ether;
    mapping(address tokenA => mapping(address tokenB => address lpToken)) public lpTokens;

    constructor(address tokenA, address tokenB, address lpToken) {
        lpTokens[tokenA][tokenB] = lpToken;
        lpTokens[tokenB][tokenA] = lpToken;
    }

    // coverage skip
    function test() public {}
    
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        IERC20(tokenA).transferFrom(msg.sender, lpTokens[tokenA][tokenB], amountADesired);
        IERC20(tokenB).transferFrom(msg.sender, lpTokens[tokenA][tokenB], amountBDesired);
        LpTokenMock(lpTokens[tokenA][tokenB]).mintTo(to, transferLpAmount);
        return (amountADesired, amountBDesired, transferLpAmount);
    }
}
