// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Auth, Authority} from "solmate/auth/authorities/RolesAuthority.sol";

import {StratX4} from "./StratX4.sol";

contract Keeper is Auth {
  constructor(Authority _authority) Auth(address(0), _authority) {}

  function batchEarn(
    address[] calldata strats,
    address[] calldata earnedAddresses,
    uint256[] calldata minAmountsOut
  )
    external
    requiresAuth
    returns (uint256[] memory profits)
  {
    require(strats.length == earnedAddresses.length);

    for (uint256 i; i < strats.length;) {
      try StratX4(strats[i]).earn(earnedAddresses[i], minAmountsOut[i]) returns (uint256 profit) {
        profits[i] = profit;
      } catch {}
      i++;
    }
  }
}
