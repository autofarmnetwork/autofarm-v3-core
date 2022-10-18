// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Authority} from "solmate/auth/Auth.sol";

import {StratX4TestBase, StratX4UserTest, StratX4EarnTest} from "../StratX4TestBase.sol";
import {Strat, EarnConfig} from "../../src/implementations/MasterchefLP1.sol";
import {LibVaultDeployJson} from "../../src/test_helpers/LibVaultDeployJson.sol";

abstract contract TestBase is StratX4TestBase {
  constructor() StratX4TestBase("bsc", 1000) {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, vm.envString("STRAT_DEPLOY_CONFIG_FILE"));
    string memory json = vm.readFile(path);

    (
      address asset,
      address farmContractAddress,
      address tokenBase,
      address tokenOther,
      uint256 pid,
      EarnConfig memory earnConfig
    ) = LibVaultDeployJson.loadVaultDeployJson(vm, json);

    /*
    strat = new Strat(
      asset,
      tokenBase,
      tokenOther,
      farmContractAddress,
      pid,
      bytes4(keccak256("pending")),
      address(0),
      0,
      Authority(address(0)),
      earnConfig
    );
    */
  }
}

contract UserTest is StratX4UserTest, TestBase {}

contract EarnTest is StratX4EarnTest, TestBase {}
