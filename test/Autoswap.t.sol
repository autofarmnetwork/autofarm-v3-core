// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "solmate/tokens/ERC20.sol";
import "@uniswap/v2-core/interfaces/IUniswapV2Factory.sol";
import {AutoSwapV5} from "../src/Autoswap.sol";

/*
Requirements:
Happy Paths:
	- swap from / to eth
	- swap from / to tokens
	- swap with multiple intermediate swaps (A -> B -> C)
	- swap with multiple dexes
	- swap to LP
Sad Paths:
	- invalid dex
	- minOutAmount not met
	- LP: minOutAmount0/1 not met
	- invalid swaps
	- leftover tokens (swaps array bought token that's not converted out, or wrong ordering)*/

string constant CHAIN = "bsc";
uint256 constant BLOCK = 20770469;
address payable constant WETHAddress =
  payable(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
address constant factoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
address constant factoryAddress1 = 0x858E3312ed3A876947EA49d572A7C42DE08af7EE;

address constant AUTO = 0xa184088a740c695E156F91f5cC086a06bb78b827;
address constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;

contract AutoswapTest is Test {
  AutoSwapV5 public autoswap;

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl(CHAIN), BLOCK);
    autoswap = new AutoSwapV5(WETHAddress);
    autoswap.setDex(
      factoryAddress,
      AutoSwapV5.DexConfig({
        fee: 9970,
        dexType: AutoSwapV5.RouterTypes.Uniswap,
        INIT_HASH_CODE: 0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5
      })
    );
    autoswap.setDex(
      factoryAddress1,
      AutoSwapV5.DexConfig({
        fee: 9980,
        dexType: AutoSwapV5.RouterTypes.Uniswap,
        INIT_HASH_CODE: 0xfea293c909d87cd4153593f077b76bb7e94340200f4ee84211ae8e4f9bd7ffdf
      })
    );
  }

  // Swap from BNB to AUTO
  function testSimpleSwapFromETH(uint96 amountIn) public {
    vm.assume(amountIn > 0.1 ether);
    vm.deal(msg.sender, amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = factoryAddress;

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: WETHAddress,
      tokenOut: AUTO,
      relativeAmounts: relativeAmounts
    });

    uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    uint256 outAmount = autoswap.swapFromETH{value: amountIn}(
      1, AUTO, dexes, swaps, address(this), block.timestamp
    );
    assertEq(outAmount, ERC20(AUTO).balanceOf(address(this)) - balanceBefore);
  }

  function testSimpleSwapToETH(uint96 amountIn) public {
    vm.assume(amountIn > 0.1 ether);
    deal(AUTO, address(this), amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = factoryAddress;

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: AUTO,
      tokenOut: WETHAddress,
      relativeAmounts: relativeAmounts
    });

    ERC20(AUTO).approve(address(autoswap), amountIn);

    uint256 balanceBefore = address(this).balance;
    uint256 outAmount = autoswap.swapToETH(
      AUTO, amountIn, 1, dexes, swaps, address(this), block.timestamp
    );

    assertEq(outAmount, address(this).balance - balanceBefore);
  }

  function testSimpleSwap(uint96 amountIn) public {
    vm.assume(amountIn > 0.1 ether);
    deal(WETHAddress, address(this), amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = factoryAddress;

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: WETHAddress,
      tokenOut: AUTO,
      relativeAmounts: relativeAmounts
    });

    ERC20(WETHAddress).approve(address(autoswap), amountIn);

    uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    uint256 outAmount = autoswap.swap(
      WETHAddress,
      AUTO,
      amountIn,
      1,
      dexes,
      swaps,
      address(this),
      block.timestamp
    );

    assertEq(outAmount, ERC20(AUTO).balanceOf(address(this)) - balanceBefore);
  }

  function testIntermediateSwap(uint96 amountIn) public {
    vm.assume(amountIn > 0.1 ether);
    deal(CAKE, address(this), amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = factoryAddress;

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](2);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts0 =
      new AutoSwapV5.RelativeAmount[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts1 =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts0[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    relativeAmounts1[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: CAKE,
      tokenOut: WETHAddress,
      relativeAmounts: relativeAmounts0
    });
    swaps[1] = AutoSwapV5.OneSwap({
      tokenIn: WETHAddress,
      tokenOut: AUTO,
      relativeAmounts: relativeAmounts1
    });

    ERC20(CAKE).approve(address(autoswap), amountIn);

    uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    uint256 outAmount = autoswap.swap(
      CAKE, AUTO, amountIn, 1, dexes, swaps, address(this), block.timestamp
    );

    assertEq(outAmount, ERC20(AUTO).balanceOf(address(this)) - balanceBefore);
  }

  /*
  function testGetLiquiditiesForTokenPair() public view {
   (uint112[2][] memory liquidities, uint256 totalLiquidity) = autoswap.getLiquiditiesForTokenPair(WETHAddress, AUTO);
   console.log(liquidities[0][0]);
   console.log(liquidities[1][0]);
   console.log(totalLiquidity);
  }
  */

  function testSplitSwap(uint96 amountIn) public {
    /*
    (uint112[2][] memory liquidities, uint256 totalLiquidity) = autoswap.getLiquiditiesForTokenPair(WETHAddress, AUTO);
    */

    vm.assume(amountIn > 0.1 ether);
    deal(WETHAddress, address(this), amountIn);
    address[] memory dexes = new address[](2);
    dexes[0] = factoryAddress;
    dexes[1] = factoryAddress1;

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](2);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 5e7, data: ""});
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 1, amount: 5e7, data: ""});
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: WETHAddress,
      tokenOut: AUTO,
      relativeAmounts: relativeAmounts
    });

    ERC20(WETHAddress).approve(address(autoswap), amountIn);

    uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    uint256 outAmount = autoswap.swap(
      WETHAddress,
      AUTO,
      amountIn,
      1,
      dexes,
      swaps,
      address(this),
      block.timestamp
    );

    assertEq(outAmount, ERC20(AUTO).balanceOf(address(this)) - balanceBefore);
  }

  function testSwapToLP1_1() public {
    uint256 outAmount = testSwapToLP1(1 ether);
    console.log(outAmount);
  }

  function testSwapToLP1(uint96 amountIn) public returns (uint256 outAmount) {
    vm.assume(amountIn > 0.1 ether);
    deal(CAKE, address(this), amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = factoryAddress;

    AutoSwapV5.OneSwap[] memory swapsToBase = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    swapsToBase[0] = AutoSwapV5.OneSwap({
      tokenIn: CAKE,
      tokenOut: WETHAddress,
      relativeAmounts: relativeAmounts
    });

    ERC20(CAKE).approve(address(autoswap), amountIn);

    // uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    outAmount = autoswap.swapToLP1(
      CAKE,
      amountIn,
      dexes,
      AutoSwapV5.LP1SwapOptions({
        base: WETHAddress,
        token: AUTO,
        amountOutMin0: 1,
        amountOutMin1: 1,
        swapsToBase: swapsToBase
      }),
      block.timestamp
    );

    // assertEq(outAmount, ERC20(AUTO).balanceOf(address(this)) - balanceBefore);
  }

  function testSwapToLP1FromETH(uint96 amountIn)
    public
    returns (uint256 outAmount)
  {
    vm.assume(amountIn > 0.1 ether);

    address[] memory dexes = new address[](1);
    dexes[0] = factoryAddress;

    AutoSwapV5.OneSwap[] memory noSwaps = new AutoSwapV5.OneSwap[](0);

    // uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    outAmount = autoswap.swapToLP1FromETH{value: amountIn}(
      dexes,
      AutoSwapV5.LP1SwapOptions({
        base: WETHAddress,
        token: AUTO,
        amountOutMin0: 1,
        amountOutMin1: 1,
        swapsToBase: noSwaps
      }),
      block.timestamp
    );

    // assertEq(outAmount, ERC20(AUTO).balanceOf(address(this)) - balanceBefore);
  }

  receive() external payable {}
}
