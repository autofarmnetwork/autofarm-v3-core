// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import "@uniswap/v2-core/interfaces/IUniswapV2Factory.sol";
import {AutoSwapV5} from "../src/Autoswap.sol";
import {UniswapTestBase} from "./test-bases/UniswapTestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockStrat} from "./mocks/MockStrat.sol";

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

bytes32 constant PERMIT_TYPEHASH = keccak256(
  "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
);

contract AutoswapTest is UniswapTestBase {
  AutoSwapV5 public autoswap;
  WETH public weth = new WETH();
  address public factory2;

  address public immutable AUTO = address(new MockERC20());
  address public immutable CAKE = address(new MockERC20());

  receive() external payable {}

  function setUp() public {
    // Add underlying ETH for WETH
    deal(address(weth), 100 ether);

    factory2 = deployFactory();
    vm.label(factory2, "Factory2");

    autoswap = new AutoSwapV5(payable(address(weth)), address(this));
    autoswap.setDex(
      address(factory),
      AutoSwapV5.DexConfig({
        fee: 9970,
        dexType: AutoSwapV5.RouterTypes.Uniswap,
        INIT_HASH_CODE: bytes32(0)
      })
    );

    autoswap.setDex(
      address(factory2),
      AutoSwapV5.DexConfig({
        fee: 9970,
        dexType: AutoSwapV5.RouterTypes.Uniswap,
        INIT_HASH_CODE: bytes32(0)
      })
    );

    addLiquidity(AUTO, address(weth), 1 ether, 1 ether, address(0));
    addLiquidityForFactory(
      AUTO, address(weth), 1 ether, 1 ether, address(0), factory2
    );
    addLiquidity(AUTO, CAKE, 1 ether, 1 ether, address(0));
    addLiquidity(address(weth), CAKE, 1 ether, 1 ether, address(0));
  }

  // Swap from BNB to AUTO
  function testSimpleSwapFromETH(uint96 amountIn) public {
    vm.assume(amountIn > 0.1 ether);
    vm.deal(msg.sender, amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: payable(address(weth)),
      tokenOut: AUTO,
      relativeAmounts: relativeAmounts
    });

    uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    uint256 outAmount = autoswap.swapFromETH{value: amountIn}(
      1, AUTO, dexes, swaps, payable(address(this)), block.timestamp
    );
    assertEq(outAmount, ERC20(AUTO).balanceOf(address(this)) - balanceBefore);
  }

  function testSimpleSwapToETH(uint96 amountIn) public {
    vm.assume(amountIn > 0.1 ether);
    deal(AUTO, address(this), amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: AUTO,
      tokenOut: payable(address(weth)),
      relativeAmounts: relativeAmounts
    });

    ERC20(AUTO).approve(address(autoswap), amountIn);

    uint256 balanceBefore = address(this).balance;
    uint256 outAmount = autoswap.swapToETH(
      AUTO, amountIn, 1, dexes, swaps, payable(address(this)), block.timestamp
    );

    assertEq(outAmount, address(this).balance - balanceBefore);
  }

  function testSimpleSwap(uint96 amountIn) public {
    vm.assume(amountIn > 0.1 ether);
    deal(payable(address(weth)), address(this), amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: payable(address(weth)),
      tokenOut: AUTO,
      relativeAmounts: relativeAmounts
    });

    ERC20(payable(address(weth))).approve(address(autoswap), amountIn);

    uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    uint256 outAmount = autoswap.swap(
      payable(address(weth)),
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
    dexes[0] = address(factory);

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
      tokenOut: payable(address(weth)),
      relativeAmounts: relativeAmounts0
    });
    swaps[1] = AutoSwapV5.OneSwap({
      tokenIn: payable(address(weth)),
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

  function testSplitSwap(uint96 amountIn) public {
    vm.assume(amountIn > 0.1 ether);
    deal(payable(address(weth)), address(this), amountIn);
    address[] memory dexes = new address[](2);
    dexes[0] = address(factory);
    dexes[1] = address(factory2);

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](2);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 5e7, data: ""});
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 1, amount: 5e7, data: ""});
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: payable(address(weth)),
      tokenOut: AUTO,
      relativeAmounts: relativeAmounts
    });

    ERC20(payable(address(weth))).approve(address(autoswap), amountIn);

    uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    uint256 outAmount = autoswap.swap(
      payable(address(weth)),
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

  function testSwapToLP1(uint96 amountIn) public returns (uint256 outAmount) {
    vm.assume(amountIn > 0.1 ether);
    deal(CAKE, address(this), amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);

    AutoSwapV5.OneSwap[] memory swapsToBase = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});
    swapsToBase[0] = AutoSwapV5.OneSwap({
      tokenIn: CAKE,
      tokenOut: payable(address(weth)),
      relativeAmounts: relativeAmounts
    });

    ERC20(CAKE).approve(address(autoswap), amountIn);

    outAmount = autoswap.swapToLP1(
      CAKE,
      amountIn,
      dexes,
      AutoSwapV5.LP1SwapOptions({
        base: payable(address(weth)),
        token: AUTO,
        amountOutMin0: 1,
        amountOutMin1: 1,
        swapsToBase: swapsToBase
      }),
      block.timestamp
    );
  }

  function testSwapToLP1FromETH(uint96 amountIn)
    public
    returns (uint256 outAmount)
  {
    vm.assume(amountIn > 0.1 ether);

    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);

    AutoSwapV5.OneSwap[] memory noSwaps = new AutoSwapV5.OneSwap[](0);

    // uint256 balanceBefore = ERC20(AUTO).balanceOf(address(this));
    outAmount = autoswap.swapToLP1FromETH{value: amountIn}(
      dexes,
      AutoSwapV5.LP1SwapOptions({
        base: payable(address(weth)),
        token: AUTO,
        amountOutMin0: 1,
        amountOutMin1: 1,
        swapsToBase: noSwaps
      }),
      block.timestamp
    );

    // assertEq(outAmount, ERC20(AUTO).balanceOf(address(this)) - balanceBefore);
  }

  function testSwapFromLP1() public {
    (address pair, uint256 liquidity) =
      addLiquidity(AUTO, CAKE, 1 ether, 1 ether, address(this));
    ERC20(pair).approve(address(autoswap), liquidity);

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](0);

    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);
    autoswap.swapFromLP1(
      CAKE,
      liquidity,
      1,
      dexes,
      AutoSwapV5.SwapFromLP1Options({lpSubtokenIn: AUTO, lpSubtokenOut: CAKE}),
      swaps,
      block.timestamp
    );
  }
}

contract AutoswapZapTest is UniswapTestBase {
  AutoSwapV5 public autoswap;
  WETH public weth = new WETH();
  address public immutable TOKEN0 = address(new MockERC20());
  address public immutable TOKEN1 = address(new MockERC20());

  uint256 public userPrivateKey = 0xBEEF;
  address public user = vm.addr(userPrivateKey);
  MockStrat public strat;
  address public asset;

  function setUp() public {
    autoswap = new AutoSwapV5(payable(address(weth)), address(this));
    autoswap.setDex(
      address(factory),
      AutoSwapV5.DexConfig({
        fee: 9970,
        dexType: AutoSwapV5.RouterTypes.Uniswap,
        INIT_HASH_CODE: bytes32(0)
      })
    );

    (asset,) = addLiquidity(TOKEN0, TOKEN1, 1 ether, 1 ether, address(0));

    strat = new MockStrat(
      asset,
      makeAddr("farm"),
      makeAddr("feesController"),
      Authority(address(0))
    );
  }

  function createPermit(
    bytes32 domainSeperator,
    address spender,
    uint256 amount
  ) internal returns (AutoSwapV5.Permit memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      userPrivateKey,
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          domainSeperator,
          keccak256(
            abi.encode(
              PERMIT_TYPEHASH, user, spender, amount, 0, block.timestamp
            )
          )
        )
      )
    );
    return AutoSwapV5.Permit({v: v, r: r, s: s});
  }

  function testZapToLP1(uint96 amountIn) public returns (uint256 outAmount) {
    vm.assume(amountIn > 0.1 ether);
    addLiquidity(TOKEN0, address(weth), 1 ether, 1 ether, address(0));
    deal(address(weth), address(this), amountIn);
    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);

    AutoSwapV5.OneSwap[] memory swapsToBase = new AutoSwapV5.OneSwap[](1);
    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});

    swapsToBase[0] = AutoSwapV5.OneSwap({
      tokenIn: payable(address(weth)),
      tokenOut: TOKEN0,
      relativeAmounts: relativeAmounts
    });

    ERC20(address(weth)).approve(address(autoswap), amountIn);

    uint256 amountOut0;
    uint256 amountOut1;
    (outAmount, amountOut0, amountOut1) = autoswap.zapToLP1(
      address(weth),
      amountIn,
      dexes,
      AutoSwapV5.LP1SwapOptions({
        base: TOKEN0,
        token: TOKEN1,
        amountOutMin0: 1,
        amountOutMin1: 1,
        swapsToBase: swapsToBase
      }),
      block.timestamp,
      address(strat)
    );

    assertEq(MockStrat(strat).balanceOf(address(this)), outAmount);
  }

  function testZapFromLP1() public {
    (, uint256 liquidity) = addLiquidity(TOKEN0, TOKEN1, 1 ether, 1 ether, user);

    deal(asset, address(strat), liquidity);
    deal(address(strat), user, liquidity);

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](0);

    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);

    assertGt(
      strat.previewRedeem(liquidity), 0, "there should be assets to redeem"
    );

    vm.prank(user);
    ERC20(strat).approve(address(autoswap), liquidity);

    vm.prank(user);
    autoswap.zapFromLP1Strat(
      TOKEN1,
      liquidity,
      1,
      dexes,
      AutoSwapV5.SwapFromLP1Options({
        lpSubtokenIn: TOKEN0,
        lpSubtokenOut: TOKEN1
      }),
      swaps,
      block.timestamp,
      address(strat)
    );
  }

  function testZapFromLP1ToETH() public {
    (, uint256 liquidity) = addLiquidity(TOKEN0, TOKEN1, 1 ether, 1 ether, user);
    addLiquidity(TOKEN1, address(weth), 1 ether, 1 ether, address(0));

    deal(address(weth), type(uint256).max);
    deal(asset, address(strat), liquidity);
    deal(address(strat), user, liquidity);

    AutoSwapV5.RelativeAmount[] memory relativeAmounts =
      new AutoSwapV5.RelativeAmount[](1);
    relativeAmounts[0] =
      AutoSwapV5.RelativeAmount({dexIndex: 0, amount: 1e8, data: ""});

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](1);
    swaps[0] = AutoSwapV5.OneSwap({
      tokenIn: TOKEN1,
      tokenOut: payable(address(weth)),
      relativeAmounts: relativeAmounts
    });
    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);

    assertGt(
      strat.previewRedeem(liquidity), 0, "there should be assets to redeem"
    );

    vm.prank(user);
    ERC20(strat).approve(address(autoswap), liquidity);

    vm.prank(user);
    autoswap.zapFromLP1StratToETH(
      liquidity,
      1,
      dexes,
      AutoSwapV5.SwapFromLP1Options({
        lpSubtokenIn: TOKEN0,
        lpSubtokenOut: TOKEN1
      }),
      swaps,
      block.timestamp,
      address(strat)
    );
  }

  function testZapFromLP1WithPermit() public {
    (, uint256 liquidity) = addLiquidity(TOKEN0, TOKEN1, 1 ether, 1 ether, user);

    deal(asset, address(strat), liquidity);
    deal(address(strat), user, liquidity);

    AutoSwapV5.Permit memory permit =
      createPermit(strat.DOMAIN_SEPARATOR(), address(autoswap), liquidity);

    AutoSwapV5.OneSwap[] memory swaps = new AutoSwapV5.OneSwap[](0);
    address[] memory dexes = new address[](1);
    dexes[0] = address(factory);

    assertGt(
      strat.previewRedeem(liquidity), 0, "there should be assets to redeem"
    );

    vm.prank(user);
    autoswap.zapFromLP1StratWithPermit(
      TOKEN1,
      liquidity,
      1,
      dexes,
      AutoSwapV5.SwapFromLP1Options({
        lpSubtokenIn: TOKEN0,
        lpSubtokenOut: TOKEN1
      }),
      swaps,
      block.timestamp,
      address(strat),
      permit
    );
  }

  receive() external payable {}
}
