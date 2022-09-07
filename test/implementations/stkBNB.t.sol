// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {StratX4TestBase, StratX4UserTest, StratX4EarnTest} from "../StratX4TestBase.sol";

import {Strat, CHAIN, TEST_BLOCK} from "../../src/implementations/stkBNB.sol";

abstract contract TestBase is StratX4TestBase {
  constructor() StratX4TestBase(CHAIN, TEST_BLOCK) {
    strat = new Strat(defaultFeeConfig, auth);
  }
}

contract UserTest is StratX4UserTest, TestBase {}

contract EarnTest is StratX4EarnTest, TestBase {}
