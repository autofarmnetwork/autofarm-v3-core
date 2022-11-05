// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";
import "forge-std/console2.sol";

import {CREATE3Factory} from "create3-factory/CREATE3Factory.sol";
import {
  MultiRolesAuthority,
  Authority
} from "solmate/auth/authorities/MultiRolesAuthority.sol";

import {Roles, setupRoleCapabilities} from "../src/auth/Auth.sol";
import {AutofarmFeesController} from "../src/FeesController.sol";
import {Keeper} from "../src/Keeper.sol";

struct AddrRoleJson {
  address addr;
  uint256 role;
}

contract DeployAutofarm is Script {
  using stdJson for string;

  function run() public {
    vm.startBroadcast();

    CREATE3Factory factory = new CREATE3Factory{salt: "AUTOFARM_CREATE3_FACTORY"}();

    address auth = factory.deploy(
      keccak256("V3_AUTHORITY"),
      abi.encodePacked(
        type(MultiRolesAuthority).creationCode,
        abi.encode(msg.sender, Authority(address(0)))
      )
    );

    console.log("Authority deployed", auth);
    console2.logBytes(abi.encode(msg.sender, Authority(address(0))));

    address feesController = factory.deploy(
      keccak256("V3_FEES_CONTROLLER"),
      abi.encodePacked(
        type(AutofarmFeesController).creationCode,
        abi.encode(
          MultiRolesAuthority(auth),
          vm.envAddress("TREASURY_ADDRESS"),
          vm.envAddress("SAV_ADDRESS"),
          block.chainid == 56 ? 64 : 255,
          0
        )
      )
    );

    console.log("FeesController deployed", feesController);

    address keeper = factory.deploy(
      keccak256("V3_KEEPER"),
      abi.encodePacked(
        type(Keeper).creationCode,
        abi.encode(feesController, MultiRolesAuthority(auth))
      )
    );

    console.log("Keeper deployed", keeper);
    console2.logBytes(
      abi.encode(feesController, MultiRolesAuthority(auth))
    );

    setupRoleCapabilities(MultiRolesAuthority(auth));
    setupAddrRoles(MultiRolesAuthority(auth));

    vm.stopBroadcast();
  }

  function setupAddrRoles(MultiRolesAuthority authority) internal {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, "/config/roles.json");
    string memory json = vm.readFile(path);

    AddrRoleJson[] memory teamRoles =
      abi.decode(vm.parseJson(json), (AddrRoleJson[]));
    for (uint256 i; i < teamRoles.length; i++) {
      authority.setUserRole(teamRoles[i].addr, uint8(teamRoles[i].role), true);
    }
  }
}
