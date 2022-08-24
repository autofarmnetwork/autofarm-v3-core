// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {FeeConfig} from "../../src/StratX4.sol";
import {
  SwapConfig, LP1EarnConfig
} from "../../src/libraries/StratX4LibEarn.sol";
import {StratX4_Masterchef_LP1} from "../../src/implementations/example.sol";

import {
  StratX4TestBase,
  StratX4UserTest,
  StratX4EarnTest
} from "../StratX4TestBase.sol";
import "constants/tokens.sol";
import "constants/chains.sol";

string constant RPC_URL = BSC_RPC_URL;
address constant dexFactory = 0x858E3312ed3A876947EA49d572A7C42DE08af7EE;
address constant dexRouter = 0x3a6d8cA21D1CF76F653A67577FA0D27453350dD8;
address constant dexFarm = 0xDbc1A13490deeF9c3C12b44FE77b503c1B061739;
uint256 constant pid = 87;
string constant pendingRewards = "pendingBSW(uint256,address)";
// uint256 constant dexSwapFee = 9980;
uint256 constant dexSwapFee = 0; // dynamic fees

address constant treasury = 0x8f95f25ff3eCb84e83B8DEd75670e377484FC5A8;
address constant SAV = 0xFaBbf2Ae3E337f7442fDaB0483226A6B977A6432;

address constant LP_TOKEN = 0xa34E97d80b76315665687E36c0E8b7f6a611685F;
address constant REWARD = 0x965F527D9159dCe6288a2219DB51fc6Eef120dD1; // BSW

abstract contract TestBase is StratX4TestBase {
  constructor() StratX4TestBase(RPC_URL) {
    SwapConfig[] memory swapsToBase = new SwapConfig[](1);
    swapsToBase[0] =
      SwapConfig({pair: BSW_BNB_PAIR, swapFee: dexSwapFee, tokenOut: WBNB});

    address[] memory baseToRewardPath = new address[](2);
    baseToRewardPath[0] = WBNB;
    baseToRewardPath[1] = REWARD;

    strat = new StratX4_Masterchef_LP1(
  	WBNB_AUTO_PAIR,
  	REWARD,
  	dexFarm,
  	pid,
  	bytes4(keccak256(abi.encodePacked(pendingRewards))),
  	FeeConfig({
  		feeRate: FEE_RATE,
  		feesController: feesController
  	}),
  	auth,
  	LP1EarnConfig({
  		earnedToBasePath: swapsToBase,
  		tokenBase: WBNB,
  		tokenOther: AUTO,
  		pairSwapFee: dexSwapFee,
  		oracleRouter: dexRouter,
  		baseToEthPath: new address[](0),
  		baseToRewardPath: baseToRewardPath
  	})
  );
  }
}

contract UserTest is StratX4UserTest, TestBase {}

contract EarnTest is StratX4EarnTest, TestBase {}
