// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {FeeConfig} from "../../src/StratX4.sol";
import {SwapConfig, LP1EarnConfig} from "../../src/libraries/StratX4LibEarn.sol";

import {StratX4TestBase, StratX4UserTest, StratX4EarnTest} from "../StratX4TestBase.sol";
import "constants/tokens.sol";

import {StratX4_WBNB_stkBNB} from "../../src/implementations/stkBNB.sol";

string constant CHAIN = "bsc";
uint256 constant BLOCK = 20770469;
address constant dexFactory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
address constant dexRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
address constant dexFarm = 0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652;
uint256 constant pid = 114;
uint256 constant dexSwapFee = 9975;

address constant treasury = 0x8f95f25ff3eCb84e83B8DEd75670e377484FC5A8;
address constant SAV = 0xFaBbf2Ae3E337f7442fDaB0483226A6B977A6432;

address constant stkBNB = 0xc2E9d07F66A89c44062459A47a0D2Dc038E4fb16;
address constant WBNB_stkBNB_PAIR = 0xaA2527ff1893e0D40d4a454623d362B79E8bb7F1;

abstract contract TestBase is StratX4TestBase {
  constructor() StratX4TestBase(CHAIN, BLOCK) {
    strat = new StratX4_WBNB_stkBNB(
   	FeeConfig({
   		feeRate: FEE_RATE,
   		feesController: feesController
   	}),
   	auth
   );
  }
}

contract UserTest is StratX4UserTest, TestBase {}

contract EarnTest is StratX4EarnTest, TestBase {}
