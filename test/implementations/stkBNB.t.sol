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

address constant dexFactory = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
address constant dexRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
address constant dexFarm = 0xa5f8C5Dbd5F286960b9d90548680aE5ebFf07652;
uint256 constant pid = 114;
uint256 constant dexSwapFee = 9975;

address constant treasury = 0x8f95f25ff3eCb84e83B8DEd75670e377484FC5A8;
address constant SAV = 0xFaBbf2Ae3E337f7442fDaB0483226A6B977A6432;

address constant CAKE_BNB_PAIR = 0x0eD7e52944161450477ee417DE9Cd3a859b14fD0;
address constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
address constant stkBNB = 0xc2E9d07F66A89c44062459A47a0D2Dc038E4fb16;
address constant WBNB_stkBNB_PAIR = 0xaA2527ff1893e0D40d4a454623d362B79E8bb7F1;

abstract contract TestBase is StratX4TestBase {
  constructor() StratX4TestBase(BSC_RPC_URL) {
    SwapConfig[] memory swapsToBase = new SwapConfig[](1);
    swapsToBase[0] =
      SwapConfig({pair: CAKE_BNB_PAIR, swapFee: dexSwapFee, tokenOut: WBNB});

    address[] memory baseToRewardPath = new address[](2);
    baseToRewardPath[0] = WBNB;
    baseToRewardPath[1] = CAKE;

    strat = new StratX4_Masterchef_LP1(
  	WBNB_stkBNB_PAIR,
  	CAKE,
  	dexFarm,
  	pid,
  	bytes4(keccak256(abi.encodePacked("pendingCake(uint256,address)"))),
  	FeeConfig({
  		feeRate: FEE_RATE,
  		feesController: feesController
  	}),
  	auth,
  	LP1EarnConfig({
  		earnedToBasePath: swapsToBase,
  		tokenBase: WBNB,
  		tokenOther: stkBNB,
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
