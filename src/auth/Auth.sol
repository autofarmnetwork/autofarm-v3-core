// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {
  MultiRolesAuthority,
  Authority
} from "solmate/auth/authorities/MultiRolesAuthority.sol";

import {StratX4} from "../StratX4.sol";
import {AutofarmFeesController} from "../FeesController.sol";
import "forge-std/console2.sol";

address constant deployer = 0xF482404f0Ee4bbC780199b2995A43882a8595adA;
address constant keeper = 0xa30A8F8F45ba4Eeaa3E0b46AECdE1Fe7d7d8A0AF;

enum Roles {
  NoAuth,
  Keeper, // Bot
  Guardian, // e.g. Luuk / Agus
  Dev, // e.g. Freeman
  Gov  // e.g. Giraffe
}


library Configurer {
  function createAuthority() internal returns (MultiRolesAuthority authority) {
    authority = new MultiRolesAuthority(address(this), Authority(address(0)));
    authority.setAuthority(authority);
    setupRoleCapacities(authority);
  }

  function setupRoleCapacities(MultiRolesAuthority _authority) internal {
    // Keeper
    _authority.setRoleCapability(
      uint8(Roles.Keeper), StratX4.earn.selector, true
    );
    _authority.setRoleCapability(
      uint8(Roles.Keeper), StratX4.setFeeConfig.selector, true
    );
    _authority.setRoleCapability(
      uint8(Roles.Keeper), AutofarmFeesController.forwardFees.selector, true
    );

    // Guardian
    _authority.setRoleCapability(
      uint8(Roles.Guardian), StratX4.pause.selector, true
    );

    // Dev
    _authority.setRoleCapability(
      uint8(Roles.Dev), StratX4.unpause.selector, true
    );
    _authority.setRoleCapability(
      uint8(Roles.Dev), StratX4.rescueOperation.selector, true
    );

    // Gov
    _authority.setRoleCapability(
      uint8(Roles.Gov), AutofarmFeesController.setRewardCfg.selector, true
    );
  }
}
