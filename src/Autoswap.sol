// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "solmate/utils/SafeTransferLib.sol";
import "solmate/auth/Owned.sol";
import "solmate/utils/FixedPointMathLib.sol";
import "solmate/utils/SSTORE2.sol";
import "solmate/tokens/WETH.sol";

import {IUniswapV2Pair} from "./interfaces/Uniswap.sol";
import {UniswapV2Helper} from "./libraries/UniswapV2Helper.sol";
import "./libraries/SwapEncoder.sol";

import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

error DexNotWhitelisted(address dex);
error PairNotFound(address router, address token0, address token1);
error SubswapFailed(address target, address inToken, uint256 subswapInAmount);
error SubswapDexIndexOutOfBounds(
  address tokenIn,
  address tokenOut,
  uint256 relativeAmountIndex,
  uint256 dexIndex,
  uint256 dexConfigs
);

// TODOs:
// - Roles: allow multiple admins to pause/delete contract
// - Multi-token output
// - Fee on transfer tokens

string constant VERSION = "5.0.0";

contract AutoSwapV5 is Owned {
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  address payable public immutable WETHAddress;

  event Swapped(
    address indexed sender,
    address indexed inToken,
    address indexed outToken,
    uint256 amountIn,
    uint256 amountOut
  );

  enum RouterTypes {
    NullDex,
    Uniswap,
    Curve,
    Saddle
  }

  // Whitelisted dexes
  // - Uniswap forks: Factory Address
  // - Curve forks: 3pool address
  //
  // <!> NOTE:
  // - Dex fees must be synced with the dex.
  //   E.g. Biswap increased fees from 0.1 to 0.2%
  //   Swaps will fail if fee is not in sync
  struct DexConfig {
    uint256 fee;
    RouterTypes dexType;
    bytes32 INIT_HASH_CODE;
  }

  mapping(address => address) public dexConfigs;

  struct RelativeAmount {
    uint256 amount;
    uint8 dexIndex;
    bytes data;
  }

  struct OneSwap {
    address tokenIn;
    address tokenOut;
    RelativeAmount[] relativeAmounts; // over 1e4
  }

  // Since we bypass routers, we have to do checks here
  modifier ensure(uint256 deadline) {
    require(deadline >= block.timestamp, "AutoSwap: EXPIRED");
    _;
  }

  function getApiVersion() external pure returns (string memory) {
    return VERSION;
  }

  constructor(address payable _weth, address owner) Owned(owner) {
    WETHAddress = _weth;
  }

  function setDex(address dex, DexConfig calldata dexConfig) external onlyOwner {
    require(dex != address(0));
    dexConfigs[dex] = SSTORE2.write(abi.encode(dexConfig));
  }

  function swap(
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata _dexes,
    OneSwap[] calldata _swaps,
    address to,
    uint256 deadline
  ) public ensure(deadline) returns (uint256 amountOut) {
    require(amountIn > 0, "input amount should be positive");
    require(amountOutMin > 0, "minimum out amount should be positive");
    require(_swaps.length > 0, "swaps must be non-empty");

    ERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    amountOut = _performSwap(
      ERC20(tokenIn), ERC20(tokenOut), amountIn, amountOutMin, _dexes, _swaps
    );
    ERC20(tokenOut).safeTransfer(to, amountOut);
    emit Swapped(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
  }

  function swapFromETH(
    uint256 amountOutMin,
    address tokenOut,
    address[] calldata _dexes,
    OneSwap[] calldata _swaps,
    address to,
    uint256 deadline
  ) public payable ensure(deadline) returns (uint256 amountOut) {
    require(msg.value > 0, "must have value");
    require(amountOutMin > 0, "minimum out amount should be positive");
    require(_swaps.length > 0, "swaps must be non-empty");

    WETH(WETHAddress).deposit{value: msg.value}();
    amountOut = _performSwap(
      ERC20(WETHAddress),
      ERC20(tokenOut),
      msg.value,
      amountOutMin,
      _dexes,
      _swaps
    );
    ERC20(tokenOut).safeTransfer(to, amountOut);
    emit Swapped(msg.sender, WETHAddress, tokenOut, msg.value, amountOut);
  }

  function swapToETH(
    address tokenIn,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata _dexes,
    OneSwap[] calldata _swaps,
    address payable to,
    uint256 deadline
  ) public ensure(deadline) returns (uint256 amountOut) {
    require(amountIn > 0, "input amount should be positive");
    require(amountOutMin > 0, "minimum out amount should be positive");
    require(_swaps.length > 0, "swaps must be non-empty");

    ERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    amountOut = _performSwap(
      ERC20(tokenIn), ERC20(WETHAddress), amountIn, amountOutMin, _dexes, _swaps
    );
    WETH(WETHAddress).withdraw(amountOut);
    to.transfer(amountOut);
    emit Swapped(msg.sender, tokenIn, WETHAddress, amountIn, amountOut);
  }

  function _performSwap(
    ERC20 tokenIn,
    ERC20 tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata _dexes,
    OneSwap[] calldata _swaps
  ) internal returns (uint256 amountOut) {
    require(_swaps.length > 0, "swaps cannot be empty");

    DexConfig[] memory _dexConfigs = new DexConfig[](_dexes.length);
    for (uint256 i; i < _dexes.length; i++) {
      _dexConfigs[i] =
        abi.decode(SSTORE2.read(dexConfigs[_dexes[i]]), (DexConfig));
      // TODO: convert to revert Error
      if (_dexConfigs[i].dexType == RouterTypes.NullDex) {
        revert DexNotWhitelisted(_dexes[i]);
      }
    }

    for (uint256 i; i < _swaps.length;) {
      OneSwap calldata _swap = _swaps[i];
      _performSplitSwap(
        _swap,
        _swap.tokenIn == address(tokenIn)
          ? amountIn
          : ERC20(_swap.tokenIn).balanceOf(address(this)),
        _dexes,
        _dexConfigs
      );
      unchecked {
        i++;
      }
    }

    amountOut = tokenOut.balanceOf(address(this));
    if (amountOutMin > 0) {
      require(
        amountOut >= amountOutMin,
        "Return amount less than the minimum required amount"
      );
    }
  }

  function _performSplitSwap(
    OneSwap calldata _swap,
    uint256 tokenInBalance,
    address[] calldata _dexes,
    DexConfig[] memory _dexConfigs
  ) internal {
    uint256 tokenInSwapped;
    for (uint256 i; i < _swap.relativeAmounts.length;) {
      RelativeAmount calldata relativeAmount = _swap.relativeAmounts[i];
      if (relativeAmount.dexIndex >= _dexConfigs.length) {
        revert SubswapDexIndexOutOfBounds(
          _swap.tokenIn,
          _swap.tokenOut,
          i,
          relativeAmount.dexIndex,
          _dexConfigs.length
        );
      }
      DexConfig memory dexConfig = _dexConfigs[relativeAmount.dexIndex];
      address dexAddress = _dexes[relativeAmount.dexIndex];

      uint256 subswapInAmount;
      if (i == _swap.relativeAmounts.length - 1) {
        subswapInAmount = tokenInBalance - tokenInSwapped;
      } else {
        subswapInAmount = tokenInBalance.mulDivDown(relativeAmount.amount, 1e8);
      }
      if (dexConfig.dexType == RouterTypes.Uniswap) {
        UniswapV2Helper.swapWithTransferIn(
          UniswapV2Helper.getPair(
            dexAddress, dexConfig.INIT_HASH_CODE, _swap.tokenIn, _swap.tokenOut
          ),
          dexConfig.fee,
          _swap.tokenIn,
          _swap.tokenOut,
          subswapInAmount,
          address(this)
        );
      } else if (dexConfig.dexType == RouterTypes.Curve) {
        ERC20(_swap.tokenIn).safeApprove(dexAddress, subswapInAmount);
        (bool succeeded,) = dexAddress.call(
          SwapEncoder.encodeSwapCurve(subswapInAmount, relativeAmount.data)
        );
        if (!succeeded) {
          revert SubswapFailed(dexAddress, _swap.tokenIn, subswapInAmount);
        }
      } else if (dexConfig.dexType == RouterTypes.Saddle) {
        ERC20(_swap.tokenIn).safeApprove(dexAddress, subswapInAmount);
        (bool succeeded,) = dexAddress.call(
          SwapEncoder.encodeSwapSaddle(
            subswapInAmount, block.timestamp, relativeAmount.data
          )
        );
        if (!succeeded) {
          revert SubswapFailed(dexAddress, _swap.tokenIn, subswapInAmount);
        }
      } else {
        revert SubswapFailed(dexAddress, _swap.tokenIn, subswapInAmount);
      }
      tokenInSwapped += subswapInAmount;
      unchecked {
        i++;
      }
    }
  }

  // **** LP Swaps ****
  // Strategies:
  // - LP1:
  //   Buy 100% one side of the LP,
  //   then auto-buy the other side using only the LP's liquidity
  // - (TODO): LP2:
  //   Buy 100% one side of the LP,
  //   then buy the other side using multiple dexes
  // - (TODO): LP3:
  //   Buy both sides of the LP,
  //   without touching the LP's liquidity itself

  struct LP1SwapOptions {
    address base;
    address token;
    uint256 amountOutMin0;
    uint256 amountOutMin1;
    OneSwap[] swapsToBase;
  }

  struct SwapFromLP1Options {
    address lpSubtokenIn;
    address lpSubtokenOut;
  }

  event SwapToLP(
    address pair,
    address token0,
    address token1,
    uint256 amountOut,
    uint256 amountOut0,
    uint256 amountOut1
  );

  function swapToLP1FromETH(
    address[] calldata _dexes,
    LP1SwapOptions calldata lpSwapOptions,
    uint256 deadline
  ) external payable ensure(deadline) returns (uint256 amountOut) {
    require(msg.value > 0);
    require(
      lpSwapOptions.swapsToBase.length > 0 || lpSwapOptions.base == WETHAddress
    );

    WETH(WETHAddress).deposit{value: msg.value}();
    {
      (amountOut,,,) = _swapToLP1(
        WETHAddress,
        msg.value,
        _dexes,
        lpSwapOptions.swapsToBase,
        lpSwapOptions,
        msg.sender
      );
    }
  }

  function swapToLP1(
    address tokenIn,
    uint256 amountIn,
    address[] calldata _dexes,
    LP1SwapOptions calldata lpSwapOptions,
    uint256 deadline
  ) public ensure(deadline) returns (uint256 amountOut) {
    require(
      lpSwapOptions.swapsToBase.length > 0 || lpSwapOptions.base == tokenIn
    );

    ERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    {
      (amountOut,,,) = _swapToLP1(
        tokenIn,
        amountIn,
        _dexes,
        lpSwapOptions.swapsToBase,
        lpSwapOptions,
        msg.sender
      );
    }
  }

  function zapToLP1(
    address tokenIn,
    uint256 amountIn,
    address[] calldata _dexes,
    LP1SwapOptions calldata lpSwapOptions,
    uint256 deadline,
    address strat
  )
    external
    ensure(deadline)
    returns (uint256 amountOut, uint256 amountOut0, uint256 amountOut1)
  {
    require(
      lpSwapOptions.swapsToBase.length > 0 || lpSwapOptions.base == tokenIn
    );

    ERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
    address asset;
    (amountOut, asset, amountOut0, amountOut1) = _swapToLP1(
      tokenIn,
      amountIn,
      _dexes,
      lpSwapOptions.swapsToBase,
      lpSwapOptions,
      address(this)
    );
    ERC20(asset).approve(strat, amountOut);
    IERC4626(strat).deposit(amountOut, msg.sender);
  }

  function zapToLP1FromETH(
    address[] calldata _dexes,
    LP1SwapOptions calldata lpSwapOptions,
    uint256 deadline,
    address strat
  )
    external
    payable
    ensure(deadline)
    returns (uint256 amountOut, uint256 amountOut0, uint256 amountOut1)
  {
    require(
      lpSwapOptions.swapsToBase.length > 0 || lpSwapOptions.base == WETHAddress,
      "Swaps must be empty if lpSubtokenIn == tokenIn"
    );

    WETH(WETHAddress).deposit{value: msg.value}();
    address asset;
    (amountOut, asset, amountOut0, amountOut1) = _swapToLP1(
      WETHAddress,
      msg.value,
      _dexes,
      lpSwapOptions.swapsToBase,
      lpSwapOptions,
      address(this)
    );
    ERC20(asset).balanceOf(address(this));
    ERC20(asset).approve(strat, amountOut);
    IERC4626(strat).deposit(amountOut, msg.sender);
  }

  struct Permit {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  // TODO: finish
  function swapFromLP1(
    address tokenOut,
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata _dexes,
    SwapFromLP1Options calldata lpSwapOptions,
    OneSwap[] calldata _swaps,
    uint256 deadline
  ) external ensure(deadline) returns (uint256 amountOut) {
    (amountOut,) = _swapFromLP1(
      tokenOut, amountIn, _dexes, _swaps, lpSwapOptions, msg.sender, msg.sender
    );
    require(amountOut >= amountOutMin);
  }

  function zapFromLP1Strat(
    address tokenOut,
    uint256 sharesOut,
    uint256 amountOutMin,
    address[] calldata _dexes,
    SwapFromLP1Options calldata lpSwapOptions,
    OneSwap[] calldata _swaps,
    uint256 deadline,
    address strat
  ) external ensure(deadline) returns (uint256 amountOut) {
    amountOut = IERC4626(strat).redeem(sharesOut, address(this), msg.sender);

    (amountOut,) = _swapFromLP1(
      tokenOut,
      amountOut,
      _dexes,
      _swaps,
      lpSwapOptions,
      address(this),
      msg.sender
    );
    require(
      amountOut >= amountOutMin, "Output amount is less than minOutAmount"
    );
  }

  function zapFromLP1StratToETH(
    uint256 sharesOut,
    uint256 amountOutMin,
    address[] calldata _dexes,
    SwapFromLP1Options calldata lpSwapOptions,
    OneSwap[] calldata _swaps,
    uint256 deadline,
    address strat
  ) external ensure(deadline) returns (uint256 amountOut) {
    amountOut = IERC4626(strat).redeem(sharesOut, address(this), msg.sender);

    (amountOut,) = _swapFromLP1(
      WETHAddress,
      amountOut,
      _dexes,
      _swaps,
      lpSwapOptions,
      address(this),
      address(this)
    );
    require(
      amountOut >= amountOutMin, "Output amount is less than minOutAmount"
    );
    WETH(WETHAddress).withdraw(amountOut);
    payable(msg.sender).transfer(amountOut);
  }

  function zapFromLP1StratWithPermit(
    address tokenOut,
    uint256 sharesOut,
    uint256 amountOutMin,
    address[] calldata _dexes,
    SwapFromLP1Options calldata lpSwapOptions,
    OneSwap[] calldata _swaps,
    uint256 deadline,
    address strat,
    Permit calldata permit
  ) external ensure(deadline) returns (uint256 amountOut) {
    ERC20(strat).permit(
      msg.sender,
      address(this),
      sharesOut,
      deadline,
      permit.v,
      permit.r,
      permit.s
    );
    IERC4626(strat).redeem(sharesOut, address(this), msg.sender);

    (amountOut,) = _swapFromLP1(
      tokenOut,
      sharesOut,
      _dexes,
      _swaps,
      lpSwapOptions,
      address(this),
      msg.sender
    );
    require(amountOut >= amountOutMin);
  }

  function _swapToLP1(
    address tokenIn,
    uint256 amountIn,
    address[] calldata _dexes,
    OneSwap[] calldata swapsToBase,
    LP1SwapOptions calldata lpSwapOptions,
    address recipient
  )
    internal
    returns (
      uint256 amountOut,
      address pair,
      uint256 amountOut0,
      uint256 amountOut1
    )
  {
    uint256 baseAmountIn = swapsToBase.length > 0
      ? _performSwap(
        ERC20(tokenIn),
        ERC20(lpSwapOptions.base),
        amountIn,
        0,
        _dexes,
        swapsToBase
      )
      : amountIn;
    DexConfig memory dexConfig =
      abi.decode(SSTORE2.read(dexConfigs[_dexes[0]]), (DexConfig));
    pair = UniswapV2Helper.getPair(
      _dexes[0],
      dexConfig.INIT_HASH_CODE,
      lpSwapOptions.base,
      lpSwapOptions.token
    );
    uint256 swapAmount;
    (swapAmount, amountOut1) = UniswapV2Helper.calcSimpleZap(
      pair, dexConfig.fee, baseAmountIn, lpSwapOptions.base, lpSwapOptions.token
    );
    amountOut0 = baseAmountIn - swapAmount;
    require(amountOut0 >= lpSwapOptions.amountOutMin0, "amountOut0 less than min");
    require(amountOut1 >= lpSwapOptions.amountOutMin1, "amountOut1 less than min");

    amountOut = UniswapV2Helper.addLiquidityFromOneSide(
      pair,
      swapAmount,
      amountOut1,
      lpSwapOptions.base,
      lpSwapOptions.token,
      baseAmountIn,
      recipient
    );

    emit SwapToLP(
      pair,
      lpSwapOptions.base,
      lpSwapOptions.token,
      amountOut,
      amountOut0,
      amountOut1
      );
  }

  // TODO: finish
  function _swapFromLP1(
    address tokenOut,
    uint256 amountIn,
    address[] calldata _dexes,
    OneSwap[] calldata swaps,
    SwapFromLP1Options calldata lpSwapOptions,
    address owner,
    address recipient
  ) internal returns (uint256 amountOut, address pair) {
    require(
      lpSwapOptions.lpSubtokenIn != lpSwapOptions.lpSubtokenOut,
      "LP subtokens cannot be the same"
    );
    require(
      (swaps.length > 0 || lpSwapOptions.lpSubtokenOut == tokenOut)
        && !(swaps.length > 0 && lpSwapOptions.lpSubtokenOut == tokenOut),
      "Swaps must be empty if lpSubtokenOut == tokenOut"
    );

    DexConfig memory dexConfig =
      abi.decode(SSTORE2.read(dexConfigs[_dexes[0]]), (DexConfig));

    uint256 lpSubswapAmount;
    {
      pair = UniswapV2Helper.getPair(
        _dexes[0],
        dexConfig.INIT_HASH_CODE,
        lpSwapOptions.lpSubtokenIn,
        lpSwapOptions.lpSubtokenOut
      );
      if (owner == address(this)) {
        ERC20(pair).safeTransfer(pair, amountIn);
      } else {
        ERC20(pair).safeTransferFrom(owner, pair, amountIn);
      }
      (uint256 amountOut0, uint256 amountOut1) =
        IUniswapV2Pair(pair).burn(address(this));

      if (lpSwapOptions.lpSubtokenIn < lpSwapOptions.lpSubtokenOut) {
        (lpSubswapAmount, amountOut) = (amountOut0, amountOut1);
      } else {
        (lpSubswapAmount, amountOut) = (amountOut1, amountOut0);
      }
    }

    if (swaps.length == 0) {
      ERC20(tokenOut).safeTransfer(recipient, amountOut);
    }

    amountOut += UniswapV2Helper.swapWithTransferIn(
      pair,
      dexConfig.fee,
      lpSwapOptions.lpSubtokenIn,
      lpSwapOptions.lpSubtokenOut,
      lpSubswapAmount,
      swaps.length > 0 ? address(this) : recipient
    );

    if (swaps.length > 0) {
      amountOut = _performSwap(
        ERC20(lpSwapOptions.lpSubtokenOut),
        ERC20(tokenOut),
        amountOut,
        0,
        _dexes,
        swaps
      );
    }

    /*
    emit SwapFromLP(
      pair,
      lpSwapOptions.lpSubtokenIn,
      lpSwapOptions.lpSubtokenOut,
      tokenOut,
      amountOut,
      lpSubswapAmount
    );
    */
  }

  // **** ADMIN ****

  // Upgrade Guide
  //
  // Non critical update:
  //   - Keep old contract alive for a period
  // Critical update:
  //   - Destroy old contract ASAP

  function destroy(address payable _to) external onlyOwner {
    selfdestruct(_to);
  }

  receive() external payable {}
}
