// SPDX-License-Identifier: MIT
//              _         __                 __      ______  
//             | |       / _|                \ \    / /___ \ 
//   __ _ _   _| |_ ___ | |_ __ _ _ __ _ __ __\ \  / /  __) |
//  / _` | | | | __/ _ \|  _/ _` | '__| '_ ` _ \ \/ /  |__ < 
// | (_| | |_| | || (_) | || (_| | |  | | | | | \  /   ___) |
//  \__,_|\__,_|\__\___/|_| \__,_|_|  |_| |_| |_|\/   |____/ 
                                                           
pragma solidity ^0.8.13;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

interface IStratX4 {
  function rewarder() external view returns (address);
}

contract VaultRewarderTime {
  using SafeTransferLib for ERC20;

  struct UserInfo {
    uint248 rewardDebt;
    bool finished;
  }

  struct PoolInfo {
    uint40 lastRewardTime;
    uint216 accRewardsPerShare;
  }

  ERC20 public immutable strat;
  ERC20 public immutable rewardToken;
  PoolInfo public poolInfo;

  mapping(address => UserInfo) public userInfo;

  uint256 public immutable rewardTokensPerSecond;
  uint256 public immutable startTime;
  uint256 public immutable endTime;

  modifier onlyStrat() {
    require(msg.sender == address(strat), "RewardsV4: UNAUTHORIZED");
    require(IStratX4(address(strat)).rewarder() == address(this), "RewardsV4: Deprecated");
    _;
  }

  modifier whenActive() {
    require(IStratX4(address(strat)).rewarder() == address(this), "RewardsV4: Deprecated");
    _;
  }

  constructor(
    address _strat,
    address _rewardToken,
    uint256 _emission,
    uint256 _startTime,
    uint256 _endTime
  ) {
    require(
      _startTime >= block.timestamp, "start timestamp must be in the future"
    );
    require(
      _endTime > _startTime, "end timestamp must be in the future"
    );
    require(_emission > 0, "emission must be positive");
    require(_rewardToken != _strat, "Reward token cannot have the same address as strat");

    strat = ERC20(_strat);
    rewardToken = ERC20(_rewardToken);
    rewardTokensPerSecond = _emission;
    startTime = _startTime;
    endTime = _endTime;

    poolInfo.lastRewardTime = uint40(
      block.timestamp > startTime ? block.timestamp : startTime
    );
  }


  // Return reward multiplier over the given _from to _to timestamps.
  function getMultiplier(uint256 _from, uint256 _to)
    public
    view
    returns (uint256)
  {
    if (_to < _from) {
      return 0;
    }
    if (_from < startTime) {
      _from = startTime;
    }
    if (_to > endTime) {
      _to = endTime;
    }
    return _to - _from;
  }

  function pendingRewards(address _user)
    external
    view
    returns (uint256 pending)
  {
    UserInfo memory user = userInfo[_user];
    uint256 sharesTotal = strat.totalSupply();
    uint256 currentAccRewardsPerShare = poolInfo.accRewardsPerShare;
    if (block.timestamp > poolInfo.lastRewardTime && sharesTotal != 0) {
      uint256 multiplier = getMultiplier(poolInfo.lastRewardTime, block.timestamp);
      uint256 rewards = multiplier * rewardTokensPerSecond;
      currentAccRewardsPerShare =
        poolInfo.accRewardsPerShare + (rewards * 1e12 / sharesTotal);
    }
    pending = strat.balanceOf(_user) * currentAccRewardsPerShare / 1e12
      - user.rewardDebt;
  }

  function _updatePool(uint256 sharesTotal) internal returns (PoolInfo memory pool) {
    pool = poolInfo; // gas saving

    if (
      block.timestamp <= pool.lastRewardTime
      || pool.lastRewardTime > endTime
    ) {
      return pool;
    }
    if (sharesTotal == 0) {
      pool.lastRewardTime = uint40(block.timestamp);
      poolInfo = pool;
      return pool;
    }

    uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
    if (multiplier <= 0) {
      return pool;
    }
    uint256 rewards = multiplier * rewardTokensPerSecond;

    pool.accRewardsPerShare = uint216(pool.accRewardsPerShare + (rewards * 1e12 / sharesTotal));
    pool.lastRewardTime = uint40(block.timestamp);
    poolInfo = pool;
  }

  // Used to update multiple users at the same time,
  // e.g. for transfers of stake
  function updateUsersRewards(
    address[2] memory _users,
    uint256[2] memory _usersSharesPre,
    uint256[2] memory _usersSharesPost,
    uint256 _sharesTotal
  ) public onlyStrat {
    PoolInfo memory pool = _updatePool(_sharesTotal);

    _updateUserRewards(pool, _users[0], _usersSharesPre[0], _usersSharesPost[0]);
    _updateUserRewards(pool, _users[1], _usersSharesPre[1], _usersSharesPost[1]);
  }

  function updateUserRewards(
    address _user,
    uint256 _userSharesPre,
    uint256 _userSharesPost,
    uint256 _sharesTotal
  ) public onlyStrat {
    PoolInfo memory pool = _updatePool(_sharesTotal);

    _updateUserRewards(pool, _user, _userSharesPre, _userSharesPost);
  }

  function _updateUserRewards(
    PoolInfo memory pool,
    address _user,
    uint256 _userSharesPre,
    uint256 _userSharesPost
  ) internal {
    UserInfo storage user = userInfo[_user];

    uint256 pending;
    if (_userSharesPre > 0 && !user.finished) {
      pending = _userSharesPre * pool.accRewardsPerShare / 1e12 - user.rewardDebt;
    }

    if (pending > 0) {
      rewardToken.safeTransfer(_user, pending);
    }

    if (block.timestamp > endTime) {
      user.finished = true;
      return;
    }

    user.rewardDebt = uint248(_userSharesPost * pool.accRewardsPerShare / 1e12);
  }

  // In case user is owed reward, and/or they have 0 shares
  // and can't harvest by calling withdraw (0)
  function harvest(address _user) public whenActive {
    PoolInfo memory pool = _updatePool(strat.totalSupply());
    UserInfo storage user = userInfo[_user];

    uint256 pending;
    uint248 rewardDebt;
    uint256 _userShares = strat.balanceOf(_user);
    if (_userShares > 0 && !user.finished) {
      rewardDebt = uint248(_userShares * pool.accRewardsPerShare / 1e12);
      pending = rewardDebt - user.rewardDebt;
    }

    if (pending > 0) {
      rewardToken.safeTransfer(_user, pending);
    }

    if (block.timestamp > endTime) {
      user.finished = true;
      return;
    }

    user.rewardDebt = rewardDebt;
  }
}
