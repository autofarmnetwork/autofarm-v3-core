// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AutofarmFeesController} from "./FeesController.sol";

interface IAutofarm {
  function userInfo(uint256 pid, address user) external view returns (uint256);
}

contract AUTORevenueVoteController {
  uint256 public constant TERM = 2630000; // 1 month
  uint256 public constant TERM_OFFSET = 194800;
  uint256 public constant VOTING_PERIOD = 172800; // 2 days

  AutofarmFeesController public immutable feesController;
  address public immutable SAV;
  address public immutable autofarm;
  uint256 public immutable savPID;

  mapping(uint256 => mapping(uint256 => uint256)) votes;
  mapping(uint256 => mapping(address => bool)) voted;

  uint256 public constant NUM_OPTIONS = 3;
  uint8[NUM_OPTIONS] public burnRates = [0, 128, 204];

  event Vote(
    address indexed voter, uint256 indexed term, uint256 indexed option
  );

  constructor(
    address _feesController,
    address _SAV,
    uint256 _savPID,
    address _autofarm
  ) {
    feesController = AutofarmFeesController(_feesController);
    SAV = _SAV;
    savPID = _savPID;
    autofarm = _autofarm;
  }

  function vote(uint256 option) public {
    require(isNowVotingPeriod());
    require(option < NUM_OPTIONS);

    uint256 currentTerm = getCurrentTerm();
    require(!voted[currentTerm][msg.sender]);

    uint256 stake = stakeInSAV(msg.sender);
    require(stake > 0);

    votes[currentTerm][option] += stake;
    voted[currentTerm][msg.sender] = true;

    emit Vote(msg.sender, currentTerm, option);
  }

  function implementResult() public {
    require(!isNowVotingPeriod());
    uint256 currentTerm = getCurrentTerm();

    (uint256 winningOption, uint256 highestVote) =
      getTermVotingResult(currentTerm);
    require(highestVote > 0);

    feesController.setBurnPortion(burnRates[winningOption]);
  }

  function getTermVotingResult(uint256 _term)
    internal
    view
    returns (uint256 winningOption, uint256 highestVote)
  {
    for (uint256 i; i < NUM_OPTIONS; i++) {
      uint256 optionVotes = votes[_term][i];
      // When there's a tie, the order of the option is used
      if (highestVote < optionVotes) {
        highestVote = optionVotes;
        winningOption = i;
      }
    }
  }

  function getCurrentTerm() public view returns (uint256) {
    return (block.timestamp + TERM_OFFSET) / TERM;
  }

  function isNowVotingPeriod() public view returns (bool) {
    return (block.timestamp + TERM_OFFSET) % TERM <= VOTING_PERIOD;
  }

  function stakeInSAV(address user) public view returns (uint256) {
    return IAutofarm(autofarm).userInfo(savPID, user);
  }
}
