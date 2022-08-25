// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Authority} from "solmate/auth/Auth.sol";

import {Configurer} from "../src/auth/Auth.sol";
import {AutofarmFeesController} from "../src/FeesController.sol";

address constant treasury = 0x8f95f25ff3eCb84e83B8DEd75670e377484FC5A8;
address constant SAV = 0xFaBbf2Ae3E337f7442fDaB0483226A6B977A6432;

contract DeployFeesControllerScript is Script {
  function run() external {
    vm.startBroadcast();
    Authority auth = Configurer.createAuthority();

    new AutofarmFeesController(
     auth,
  	treasury,
  	SAV,
  	address(0),
  	64,
  	0
  );

    vm.stopBroadcast();
  }
}