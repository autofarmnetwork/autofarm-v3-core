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
import {
  StratX4MasterchefLP1
} from "../../src/implementations/MasterchefLP1.sol";
import {
  IUniswapV2Factory,
  IUniswapV2Router01
} from "../../src/interfaces/Uniswap.sol";

contract TestBase is Test {
  /*
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

  address public asset;
  IUniswapV2Factory public factory;
  IUniswapV2Router01 public router;
  ERC20 public tokenA;
  ERC20 public tokenB;
  ERC20 public tokenC;
  address public pairAC;
  StratX4MasterchefLP1 public strat;

  function setUp() public {
    factory = IUniswapV2Factory(
      deployCode(
        "./uniswap-build/UniswapV2Factory.json", abi.encode(address(this))
      )
    );

    console2.log(factory.feeToSetter());

    router = IUniswapV2Router01(
      deployCode(
        "./uniswap-build/UniswapV2Router02.json",
        abi.encode(address(factory), address(5))
      )
    );

    assertEq(factory.feeToSetter(), address(this), "feeSetter should be this");
    tokenA = new MockERC20();
    tokenB = new MockERC20();
    tokenC = new MockERC20();
    address pair = factory.createPair(address(tokenA), address(tokenB));
    pairAC = factory.createPair(address(tokenA), address(tokenC));
    asset = pair;

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

    deal(address(tokenA), address(this), 1 ether);
    deal(address(tokenB), address(this), 1 ether);
    ERC20(address(tokenA)).approve(address(router), 1 ether);
    ERC20(address(tokenB)).approve(address(router), 1 ether);

    router.addLiquidity(
      address(tokenA),
      address(tokenB),
      1 ether, // amountTokenDesired
      1 ether, // amountTokenDesired
      0, // amountTokenMin
      0, // amountETHMin
      address(0), // to
      10_000_000 // deadline
    );

    deal(address(tokenC), address(this), 1 ether);
    deal(address(tokenA), address(this), 1 ether);

    ERC20(address(tokenC)).approve(address(router), 1 ether);
    ERC20(address(tokenA)).approve(address(router), 1 ether);
    router.addLiquidity(
      address(tokenC),
      address(tokenA),
      1 ether, // amountTokenDesired
      1 ether, // amountTokenDesired
      0, // amountTokenMin
      0, // amountETHMin
      address(0), // to
      10_000_000 // deadline
    );

    deal(address(tokenC), address(this), type(uint256).max);
    deal(address(tokenA), address(this), 1);
    deal(address(tokenB), address(this), 1);
    deal(asset, address(this), 1);
    assertEq(
      ERC20(asset).balanceOf(address(this)),
      1,
      "initial output balance should be 1"
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
    strat.earn(address(tokenC));
  }
}
