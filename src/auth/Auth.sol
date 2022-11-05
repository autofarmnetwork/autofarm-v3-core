// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MultiRolesAuthority} from
  "solmate/auth/authorities/MultiRolesAuthority.sol";

enum Roles {
  NoAuth,
  KeeperCaller, // Keeper caller
  Keeper,
  Guardian,
  Dev,
  Gov
}

import {StratX4} from "../StratX4.sol";
import {StratX4Compounding} from "../StratX4Compounding.sol";
import {Keeper} from "../Keeper.sol";
import {AutofarmFeesController} from "../FeesController.sol";

function setupRoleCapabilities(MultiRolesAuthority auth) {
  // Keeper caller
  auth.setRoleCapability(
    uint8(Roles.KeeperCaller), Keeper.batchEarn.selector, true
  );

  // Keeper
  auth.setRoleCapability(uint8(Roles.Keeper), StratX4.earn.selector, true);
  auth.setRoleCapability(uint8(Roles.Keeper), StratX4.setFeeRate.selector, true);
  auth.setRoleCapability(
    uint8(Roles.Keeper), StratX4.collectFees.selector, true
  );
  auth.setRoleCapability(
    uint8(Roles.Keeper), AutofarmFeesController.forwardFees.selector, true
  );

  // Guardian
  auth.setRoleCapability(
    uint8(Roles.Guardian), StratX4.deprecate.selector, true
  );

  // Dev
  auth.setRoleCapability(uint8(Roles.Dev), StratX4.undeprecate.selector, true);
  auth.setRoleCapability(
    uint8(Roles.Dev), StratX4.rescueOperation.selector, true
  );
  auth.setRoleCapability(
    uint8(Roles.Dev), StratX4Compounding.addEarnConfig.selector, true
  );
  auth.setRoleCapability(
    uint8(Roles.Dev), StratX4Compounding.addHarvestConfig.selector, true
  );

  // Gov
  auth.setRoleCapability(
    uint8(Roles.Gov), AutofarmFeesController.setTreasury.selector, true
  );
  auth.setRoleCapability(
    uint8(Roles.Gov), AutofarmFeesController.setSAV.selector, true
  );
  auth.setRoleCapability(
    uint8(Roles.Gov), AutofarmFeesController.setRewardCfg.selector, true
  );
}
