// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {CREATE3} from "solmate/utils/CREATE3.sol";
import {Auth, Authority} from "solmate/auth/Auth.sol";
import {MultiRolesAuthority} from "solmate/auth/authorities/MultiRolesAuthority.sol";
import {Configurer} from "./auth/Auth.sol";
import {AutofarmFeesController} from "./FeesController.sol";

contract AutofarmDeployer is Auth {
  AutofarmFeesController public immutable feesController;

  constructor(address _treasury, address _votingController, uint8 _portionToPlatform, uint8 _portionToAUTOBurn)
    Auth(address(this), Configurer.createAuthority(msg.sender))
  {
    feesController = new AutofarmFeesController(
     authority,
     _treasury,
     _votingController,
     _portionToPlatform,
     _portionToAUTOBurn
    );
  }

  function deployStrat(bytes32 salt, bytes memory initCode) public requiresAuth returns (address) {
    bytes memory args = abi.encode(address(authority));
    bytes memory creationCode = abi.encodePacked(initCode, args);
    return CREATE3.deploy(salt, creationCode, 0);
  }

  function setUserRole(address user, uint8 role, bool enabled) public requiresAuth {
    MultiRolesAuthority(address(authority)).setUserRole(user, role, enabled);
  }
}
