// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDX is ERC20 {
    constructor() ERC20("USDX", "The ultimate stablecoin") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
