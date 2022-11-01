// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {LibString} from "solmate/utils/LibString.sol";

import {Roles, AutofarmAuthority} from "../src/auth/Auth.sol";
import {AutofarmFeesController} from "../src/FeesController.sol";
import {Keeper} from "../src/Keeper.sol";

struct AddrRoleJson {
  address addr;
  uint256 role;
}

contract DeployAutofarm is Script {
  using stdJson for string;

  string public json;

  function run() public {
    vm.startBroadcast();

    AutofarmAuthority auth =
      new AutofarmAuthority{salt: "autofarm-authority-v0"}(msg.sender);
    // setupAddrRoles(auth);
    AutofarmFeesController feesController =
    new AutofarmFeesController{salt: "autofarm-fees-v0"}(
      auth,
      vm.envAddress("TREASURY_ADDRESS"),
      vm.envAddress("SAV_ADDRESS"),
      64,
      0
    );
    Keeper keeper =
      new Keeper{salt: "autofarm-keeper-v0"}(address(feesController), auth);
    auth.setUserRole(address(keeper), uint8(Roles.Keeper), true);
    vm.stopBroadcast();
  }

  function setupAddrRoles(AutofarmAuthority authority) internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/config/roles.json");
    json = vm.readFile(path);
    AddrRoleJson[] memory teamRoles =
      abi.decode(vm.parseJson(json), (AddrRoleJson[]));
    for (uint256 i; i < teamRoles.length; i++) {
      authority.setUserRole(teamRoles[i].addr, uint8(teamRoles[i].role), true);
    }
  }
}
