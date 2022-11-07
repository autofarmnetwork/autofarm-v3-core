// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {UniswapV2Helper} from "../../src/libraries/UniswapV2Helper.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAuthority} from "../mocks/MockAuthority.sol";
import {IMinichefV2} from "../../src/interfaces/IMinichef.sol";
import {StratX4MinichefLP1} from "../../src/implementations/MinichefLP1.sol";
import {UniswapV2TestBase} from "../test-bases/UniswapV2TestBase.sol";

contract MinichefLP1Test is UniswapV2TestBase {
  address public asset;

  ERC20 public tokenA = new MockERC20();
  ERC20 public tokenB = new MockERC20();
  ERC20 public tokenC = new MockERC20();
  ERC20 public tokenD = new MockERC20();

  address public pairAC;

  StratX4MinichefLP1 public strat;

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

    uint256[] memory feeFactors = new uint256[](1);
    feeFactors[0] = 9970;
    address[] memory pairsPath = new address[](1);
    pairsPath[0] = pairAC;
    address[] memory tokensPath = new address[](2);
    tokensPath[0] = address(tokenC);
    tokensPath[1] = address(tokenA);

    UniswapV2Helper.SwapRoute memory swapRoute = UniswapV2Helper.SwapRoute({
      feeFactors: feeFactors,
      pairsPath: pairsPath,
      tokensPath: tokensPath
    });
    UniswapV2Helper.ZapLiquidityConfig memory zapLiquidityConfig = UniswapV2Helper
      .ZapLiquidityConfig({
      feeFactor: 9970,
      lpSubtokenIn: address(tokenA),
      lpSubtokenOut: address(tokenB)
    });

    strat = new StratX4MinichefLP1(
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
      abi.encodeWithSelector(IMinichefV2.withdraw.selector),
      ""
    );
    vm.mockCall(
      strat.farmContractAddress(),
      abi.encodeWithSelector(IMinichefV2.deposit.selector),
      ""
    );
    deal(address(tokenC), address(strat), amountIn);
    strat.earn(address(tokenC), 1);
  }
}
