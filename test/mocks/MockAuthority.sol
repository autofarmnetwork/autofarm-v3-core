// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Authority} from "solmate/auth/Auth.sol";

contract MockAuthority is Authority {
  function canCall(
    address, /* user */
    address, /* target */
    bytes4 /* functionSig */
  ) external pure returns (bool) {
    return true;
  }
}
