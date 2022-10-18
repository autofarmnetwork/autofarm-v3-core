// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20("MockToken", "TOKEN", 18) {
  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}
