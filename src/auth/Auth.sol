// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {
  MultiRolesAuthority,
  Authority
} from "solmate/auth/authorities/MultiRolesAuthority.sol";
import {Auth} from "solmate/auth/Auth.sol";

import {StratX4} from "../StratX4.sol";
import {Keeper} from "../Keeper.sol";
import {AutofarmFeesController} from "../FeesController.sol";

enum Roles {
  NoAuth,
  KeeperCaller, // Keeper caller
  Keeper,
  Guardian,
  Dev,
  Gov
}

contract AutofarmAuthority is MultiRolesAuthority {
  constructor(address _owner)
    MultiRolesAuthority(_owner, Authority(address(this)))
  {
    // Keeper caller
    _setRoleCapability(
      uint8(Roles.KeeperCaller), Keeper.batchEarn.selector, true
    );

    // Keeper
    _setRoleCapability(uint8(Roles.Keeper), StratX4.earn.selector, true);
    _setRoleCapability(uint8(Roles.Keeper), StratX4.setFeeRate.selector, true);
    _setRoleCapability(uint8(Roles.Keeper), StratX4.collectFees.selector, true);
    _setRoleCapability(
      uint8(Roles.Keeper), AutofarmFeesController.forwardFees.selector, true
    );

    // Guardian
    _setRoleCapability(uint8(Roles.Guardian), StratX4.deprecate.selector, true);

    // Dev
    _setRoleCapability(uint8(Roles.Dev), StratX4.undeprecate.selector, true);
    _setRoleCapability(uint8(Roles.Dev), StratX4.rescueOperation.selector, true);

    // Gov
    _setRoleCapability(
      uint8(Roles.Gov), AutofarmFeesController.setTreasury.selector, true
    );
    _setRoleCapability(
      uint8(Roles.Gov), AutofarmFeesController.setSAV.selector, true
    );
    _setRoleCapability(
      uint8(Roles.Gov), AutofarmFeesController.setRewardCfg.selector, true
    );
  }

  // Bypass requiresAuth for setting up in constructor
  function _setRoleCapability(uint8 role, bytes4 functionSig, bool enabled)
    internal
  {
    if (enabled) {
      getRolesWithCapability[functionSig] |= bytes32(1 << role);
    } else {
      getRolesWithCapability[functionSig] &= ~bytes32(1 << role);
    }

    emit RoleCapabilityUpdated(role, functionSig, enabled);
  }
}
