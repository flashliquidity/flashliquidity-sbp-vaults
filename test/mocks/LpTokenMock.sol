// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20, ERC20Mock} from "./ERC20Mock.sol";

contract LpTokenMock is ERC20Mock {
    IERC20 private immutable i_token0;
    IERC20 private immutable i_token1;

    constructor(
        address tokenA,
        address tokenB
    ) ERC20Mock("MockLP", "MOCKLP") {
        i_token0 = IERC20(tokenA);
        i_token1 = IERC20(tokenB);
    }

    // coverage skip
    function test() public {}

    function getReserves() external view returns (uint112 ,uint112 ,uint32) {
        return(
            uint112(i_token0.balanceOf(address(this))),
            uint112(i_token1.balanceOf(address(this))),
            uint32(block.timestamp)
        );
    }

    function token0() external view returns (address) {
        return address(i_token0);
    }

    function token1() external view returns (address) {
        return address(i_token1);
    }
}
