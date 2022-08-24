// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

interface IReward {
  function updateRewards(
    address userAddress,
    uint256 sharesChange,
    bool isSharesRemoved
  )
    external;
}

library StratX3Lib {

  function _harvestReward(
    address[] memory rewarders,
    address _userAddress,
    uint256 _sharesChange,
    bool _isSharesRemoved
  )
    internal
  {
    for (uint256 i = 0; i < rewarders.length; i++) {
      IReward(rewarders[i]).updateRewards(
        _userAddress, _sharesChange, _isSharesRemoved
      );
    }
  }
}
