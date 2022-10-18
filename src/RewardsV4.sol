// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "solmate/utils/SafeTransferLib.sol";
import "solmate/tokens/ERC20.sol";

import {StratX4} from "./StratX4.sol";

contract RewardsV4 {
  using SafeTransferLib for ERC20;

  struct UserInfo {
    uint256 rewardDebt;
    uint256 unpaidRewards; // In case reward cannot be paid in full
  }

  uint256 lastRewardTimestamp;
  uint256 accRewardsPerShare;

  ERC20 public immutable strat;
  ERC20 public immutable rewardToken;
  address public immutable treasuryAddress;

  mapping(address => bool) whitelist;
  mapping(address => UserInfo) public userInfo;

  bool isContractsAllowed = false;

  uint256 public rewardTokensPerSecond;
  uint256 public immutable startTimestamp;
  uint256 public immutable endTimestamp;

  event Harvest(address indexed user, uint256 amount);

  constructor(
    StratX4 _strat,
    address _rewardToken,
    address _treasury,
    uint256 _emission,
    uint256 _startTimestamp,
    uint256 _endTimestamp
  ) {
    require(_startTimestamp > block.timestamp, "start timestamp must be in the future");
    require(_endTimestamp > _startTimestamp, "end timestamp must be in the future");
    require(_emission > 0, "emission must be positive");

    // transferOwnership(msg.sender);
    strat = _strat;
    rewardToken = ERC20(_rewardToken);
    treasuryAddress = _treasury;
    rewardTokensPerSecond = _emission;
    startTimestamp = _startTimestamp;
    endTimestamp = _endTimestamp;

    lastRewardTimestamp = block.timestamp > startTimestamp ? block.timestamp : startTimestamp;
  }

  /*
    function setUserUnpaidRewardsOne(address _strat, address _user, uint256 _unpaidRewards) public onlyOwner {
      	userInfo[_user].unpaidRewards = _unpaidRewards;
    }
    function setUserUnpaidRewardsBatch(address _strat, address[] memory _users, uint256[] memory _unpaidRewards) public onlyOwner {
        for (uint i =0; i < _users.length; i++){
      	    userInfo[_users[i]].unpaidRewards = _unpaidRewards[i];
        }
    }
    */

  function setWhitelist(address _user, bool _isWhitelisted) public {
    whitelist[_user] = _isWhitelisted;
  }

  function setAllowContracts(bool _isContractsAllowed) public {
    isContractsAllowed = _isContractsAllowed;
  }

  function setEmissionPerSecond(uint256 _emission) public {
    _update(strat.totalSupply());
    rewardTokensPerSecond = _emission;
  }

  function remainingRewards() external view returns (uint256) {
    if (block.timestamp < startTimestamp) {
      return 0;
    }
    return (endTimestamp - block.timestamp) / rewardTokensPerSecond;
  }

  // Return reward multiplier over the given _from to _to block.
  function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
    if (endTimestamp == 0) {
      return _to - _from;
    }
    if (_from >= endTimestamp) {
      return 0;
    }
    if (_to >= endTimestamp) {
      return endTimestamp - _from;
    }
    return _to - _from;
  }

  function pendingRewards(address _user) external view returns (uint256 pending) {
    UserInfo storage user = userInfo[_user];
    uint256 sharesTotal = strat.totalSupply();
    uint256 currentAccRewardsPerShare = accRewardsPerShare;
    if (block.timestamp > lastRewardTimestamp && sharesTotal != 0) {
      uint256 multiplier = getMultiplier(lastRewardTimestamp, block.timestamp);
      uint256 AUTOReward = multiplier * rewardTokensPerSecond;
      currentAccRewardsPerShare = accRewardsPerShare + (AUTOReward * 1e12 / sharesTotal);
    }
    // console.log("sharesTotal is", sharesTotal);
    // console.log("user rewardDebt is", user.rewardDebt);
    // console.log("accRewardsPerShare is", accRewardsPerShare);
    pending = strat.balanceOf(_user) * currentAccRewardsPerShare / 1e12 - user.rewardDebt + user.unpaidRewards;
  }

  /*
    function update() public {
      uint256 sharesTotal = IStrategy(_strat).sharesTotal();
      return _updatePool(_strat, sharesTotal);
    }
    */

  function _update(uint256 sharesTotal) internal {
    if (block.timestamp <= lastRewardTimestamp) {
      return;
    }

    lastRewardTimestamp = block.timestamp;

    if (sharesTotal == 0) {
      return;
    }
    uint256 multiplier = getMultiplier(lastRewardTimestamp, block.timestamp);
    if (multiplier <= 0) {
      return;
    }
    uint256 AUTOReward = multiplier * rewardTokensPerSecond;

    // console.log("<!> sharesTotal is", sharesTotal);
    // console.log("<!> multiplier is", multiplier);
    // console.log("<!> AUTOReward is", AUTOReward);

    // accRewardsPerShare * sharesTotal
    accRewardsPerShare = accRewardsPerShare + (AUTOReward * 1e12 / sharesTotal);
    lastRewardTimestamp = block.timestamp;
  }

  function updateRewards(
    address _user,
    uint256 _userShares,
    uint256 _sharesTotal,
    uint256 _sharesChange,
    bool _isRemoveShares
  ) public {
    /*
        if (!_isRemoveShares && !isContractsAllowed &&
            _user.isContract() && !whitelist[_user]
        ) {
          return;
        }
        */

    uint256 newSharesTotal = _isRemoveShares ? _sharesTotal + _sharesChange : _sharesTotal - _sharesChange;
    UserInfo storage user = userInfo[_user];
    _update(newSharesTotal);
    if (_userShares > 0) {
      uint256 pending = _userShares * accRewardsPerShare / 1e12 - user.rewardDebt + user.unpaidRewards;
      if (pending > 0) {
        safeRewardsTransfer(_user, pending);
      }
    }

    // if reward contract is deployed after users have deposited
    /*
        if (_isRemoveShares && userShares < _sharesChange) {
          user.rewardDebt = 0;
          return;
        }
        */
    user.rewardDebt =
      (_isRemoveShares ? _userShares - _sharesChange : _userShares + _sharesChange) * accRewardsPerShare / 1e12;
  }

  // In case user is owed reward, and/or they have 0 shares
  // and can't harvest by calling withdraw (0)
  function harvest() public {
    _update(strat.totalSupply());
    UserInfo storage user = userInfo[msg.sender];
    uint256 userShares = strat.balanceOf(msg.sender);
    uint256 newRewardDebt = userShares * accRewardsPerShare / 1e12;
    uint256 pending = newRewardDebt - user.rewardDebt + user.unpaidRewards;
    if (pending > 0) {
      // In case reward cannot be paid in full
      safeRewardsTransfer(msg.sender, pending);
      user.rewardDebt = newRewardDebt;
    }
  }

  function safeRewardsTransfer(address _to, uint256 _requestedAmount) internal returns (uint256 unpaidRewards) {
    /*
        if (!isContractsAllowed && _to.isContract() && !whitelist[_to]) {
            return _requestedAmount;
        }
        */
    uint256 amountToSend = _requestedAmount;
    uint256 allowance = rewardToken.allowance(address(treasuryAddress), address(this));
    if (allowance < amountToSend) {
      amountToSend = allowance;
    }
    uint256 bal = rewardToken.balanceOf(address(treasuryAddress));
    if (bal < amountToSend) {
      amountToSend = bal;
    }
    unpaidRewards = _requestedAmount - amountToSend;
    if (unpaidRewards > 0) {
      userInfo[_to].unpaidRewards = unpaidRewards;
    }
    rewardToken.safeTransferFrom(treasuryAddress, _to, amountToSend);
    emit Harvest(_to, amountToSend);
  }
}
