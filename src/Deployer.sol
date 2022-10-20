// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CREATE3} from "solmate/utils/CREATE3.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {MultiRolesAuthority} from
  "solmate/auth/authorities/MultiRolesAuthority.sol";
import {Configurer} from "./auth/Auth.sol";
import {AutofarmFeesController} from "./FeesController.sol";

contract AutofarmDeployer is Auth {
  constructor(Authority auth) Auth(address(0), auth) {}

  function deployStrat(bytes32 salt, bytes memory initCode, bytes memory args)
    public
    requiresAuth
    returns (address)
  {
    bytes memory creationCode = abi.encodePacked(initCode, args);
    return CREATE3.deploy(salt, creationCode, 0);
  }
}
