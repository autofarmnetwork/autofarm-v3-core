// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {
  SwapRoute, ZapLiquidityConfig
} from "../../src/libraries/StratX4LibEarn.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAuthority} from "../mocks/MockAuthority.sol";
import {IMasterchefV2} from "../../src/interfaces/IMasterchefV2.sol";
import {StratX4MasterchefLP1} from "../../src/implementations/MasterchefLP1.sol";
import {UniswapTestBase} from "../test-bases/UniswapTestBase.sol";

contract MasterchefLP1Test is UniswapTestBase {
  address public asset;

  ERC20 public tokenA = new MockERC20(); // asset.token0
  ERC20 public tokenB = new MockERC20(); // asset.token1
  ERC20 public tokenC = new MockERC20(); // reward token

  address public pairAC;

  StratX4MasterchefLP1 public strat;

  function setUp() public {
    (asset,) = addLiquidity(
      address(tokenA),
      address(tokenB),
      1 ether, // amountTokenDesired
      1 ether, // amountTokenDesired
      address(0) // to
    );

    (pairAC,) = addLiquidity(
      address(tokenC),
      address(tokenA),
      1 ether, // amountTokenDesired
      1 ether, // amountTokenDesired
      address(0) // to
    );

    uint256[] memory swapFees = new uint256[](1);
    swapFees[0] = 9970;
    address[] memory pairsPath = new address[](1);
    pairsPath[0] = pairAC;
    address[] memory tokensPath = new address[](1);
    tokensPath[0] = address(tokenA);

    SwapRoute memory swapRoute = SwapRoute({
      swapFees: swapFees,
      pairsPath: pairsPath,
      tokensPath: tokensPath
    });
    ZapLiquidityConfig memory zapLiquidityConfig = ZapLiquidityConfig({
      swapFee: 9970,
      lpSubtokenIn: address(tokenA),
      lpSubtokenOut: address(tokenB)
    });

    strat = new StratX4MasterchefLP1(
      asset,
      makeAddr("feesController"),
      new MockAuthority(),
      makeAddr("farm"),
      0,
      address(tokenC),
      swapRoute,
      zapLiquidityConfig
    );
  }

  function testEarn(uint96 amountIn) public {
    vm.assume(amountIn > 1e4);
    vm.mockCall(
      strat.farmContractAddress(),
      abi.encodeWithSelector(IMasterchefV2.withdraw.selector),
      ""
    );
    vm.mockCall(
      strat.farmContractAddress(),
      abi.encodeWithSelector(IMasterchefV2.deposit.selector),
      ""
    );
    deal(address(tokenC), address(strat), amountIn);
    strat.earn(address(tokenC), 1);
  }
}
