pragma solidity ^0.8.13;

interface IMinichefV2 {
  struct UserInfo {
    uint256 amount;
    uint256 rewardDebt;
  }

  function deposit(uint256 _pid, uint256 _amount, address to) external;

  function withdraw(uint256 _pid, uint256 _amount, address to) external;
  function withdrawAndHarvest(uint256 _pid, uint256 _amount, address to)
    external;

  function harvest(uint256 _pid, address to) external;

  function enterStaking(uint256 _amount) external;

  function leaveStaking(uint256 _amount) external;

  function userInfo(uint256 pid, address userAddress)
    external
    view
    returns (UserInfo memory);

  function emergencyWithdraw(uint256 _pid, address to) external;
}
