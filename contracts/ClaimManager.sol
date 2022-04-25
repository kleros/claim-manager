/**
 * @authors: [@greenlucid]
 * @reviewers: []
 * @auditors: []
 * @bounties: []
 * @deployments: []
 * SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.12;
import "@kleros/erc-792/contracts/IArbitrable.sol";
import "@kleros/erc-792/contracts/IArbitrator.sol";
import "@kleros/erc-792/contracts/erc-1497/IEvidence.sol";

import "./interfaces/IClaimUtils.sol";
import "./IClaimManager.sol";
import "./LimitedClaimManager.sol";

contract ClaimManager is LimitedClaimManager, IEvidence, IClaimManager, IArbitrable {
  /**
   * 0: Don't pay. (Refuse to arbitrate)
   * 1: Deny that an insured event has happened. (Don't pay)
   * 2: Accept the claim.
   * 3: Accept the counter-claim.
   */
  uint256 internal constant RULING_OPTIONS = 3;

  enum ClaimStatus { None, Claimed, CounterOffered, Disputed, Resolved }

  struct Claim {
    uint256 arbitratorDisputeId; // prob uneeded in V2, because the mapping points here
    uint256 claimedAmount; // initial amount
    uint256 timestamp; // timestamp for whatever current stage the claim is at
    uint256 counterOfferAmount;
    address claimant;
    address beneficiary;
    ClaimStatus status;
  }

  enum Party {
      None, // Party per default when there is no challenger or requester. Also used for unconclusive ruling.
      Denial, // Party that made the request to change a status.
      AcceptClaim, // Party that challenges the request to change a status.
      AcceptCounterOffer 
    }

  struct Round {
    Party sideFunded; // Stores the side that successfully paid the appeal fees in the latest round. Note that if both sides have paid a new round is created.
    uint256 feeRewards; // Sum of reimbursable fees and stake rewards available to the parties that made contributions to the side that ultimately wins a dispute.
    uint256[3] amountPaid; // Tracks the sum paid for each Party in this round.
  }

  // EVENTS

  // _contributor is redundant because it's msg.sender. _contribution is needed because of refunds
  event Contribution(uint256 _claimId,
    uint256 _roundId,
    address indexed _contributor,
    uint256 _contribution,
    Party _side
  );

  IClaimUtils public immutable claimUtils;
  address public immutable insurer;
  IArbitrator public immutable arbitrator;
  uint256 public immutable counterOfferPeriod; // t-0 to insurer making a counter offer
  uint256 public immutable challengePeriod; // counter offer to challenge or accept

  uint256 public claimCount; // on remaking this contract, should be changed for the insurer
  bytes public arbitratorExtraData;
  mapping(uint256 => Claim) public claims;
  mapping(uint256 => uint256) public disputeIdToClaimId;

  // Appealing / contribution related data (unused)
  /** rounds[claimId][round]
  mapping(uint256 => mapping(uint256 => Round)) public rounds;
  // contributions[claimId][round][contributor][party]
  mapping(uint256 => mapping(uint256 => mapping(address => uint256[3]))) public contributions;
  */
  constructor(
      address _claimUtils,
      address _arbitrator,
      address _insurer,
      uint256 _counterOfferPeriod,
      uint256 _challengePeriod,
      string memory _metaEvidence,
      bytes memory _arbitratorExtraData,
      uint256 _claimPayoutLimitPeriod,
      uint256 _claimPayoutLimitAmount
  ) LimitedClaimManager(_claimPayoutLimitPeriod, _claimPayoutLimitAmount) {
    claimUtils = IClaimUtils(_claimUtils);
    arbitrator = IArbitrator(_arbitrator);
    insurer = _insurer;
    counterOfferPeriod = _counterOfferPeriod;
    challengePeriod = _challengePeriod;
    arbitratorExtraData = _arbitratorExtraData;
    emit MetaEvidence(0, _metaEvidence);
  }

  /**
   * intended evidence:
   * proof that claimant is authorized by the DAO to make this claim
   * proof of the damage
   * arguments defending the damage warrants a compensation
   * and an estimation of the compensation required by the terms of the policy
   */
  function claimInsurance(uint256 _claimedAmount, address _beneficiary, string calldata _evidence) external {
    Claim storage claim = claims[claimCount++];
    claim.claimant = msg.sender;
    claim.beneficiary = _beneficiary;
    claim.claimedAmount = _claimedAmount;
    claim.timestamp = block.timestamp;
    claim.status = ClaimStatus.Claimed;

    // evidenceGroupId can just be the id of the claim
    emit Evidence(arbitrator, claimCount - 1, msg.sender, _evidence);
    emit ClaimCreated(_claimedAmount);
  }

  function acceptClaim(uint256 _claimId) external {
    require(msg.sender == insurer, "Only insurer can accept claim");
    Claim storage claim = claims[_claimId];
    require(claim.timestamp + counterOfferPeriod >= block.timestamp, "Out of time to accept claim");
    require(claim.status == ClaimStatus.Claimed, "Claim must be in claimed status");
    claim.status = ClaimStatus.Resolved;
    claimUtils.payOutClaim(claim.beneficiary, claim.claimedAmount);
    emit ClaimResolved(_claimId, claim.claimedAmount);
  }

  /**
   * intended evidence
   * The insurer could post either refutal of the damage not existing
   * arguments against the damage warranting a compensation
   * or maybe accept the damage but show a different estimation of the compensation (which will be in the counterOffer)
   */

  /**
   * this function can be used for:
   * rejecting (counterOffer of 0)
   * regular counterOffer
   * counterOffer and immediately escalate
   * accept and escalate to Kleros (just counterOffer the same)
   */
  function counterOffer(uint256 _claimId, uint256 _amount, bool _toDispute, string calldata _evidence)
      external payable {
    require(msg.sender == insurer, "Only insurer can counter offer");
    Claim storage claim = claims[_claimId];
    require(claim.timestamp + counterOfferPeriod >= block.timestamp, "Out of time to counter offer");
    require(claim.status == ClaimStatus.Claimed, "Claim must be in claimed status");
    require(_amount <= claim.claimedAmount, "Counteroffer can't exceed claim");

    emit Evidence(arbitrator, _claimId, msg.sender, _evidence);
    emit CounterOffer(_claimId, _amount);
  
    claim.counterOfferAmount = _amount;
    if (_toDispute) {
      // insurer will pay the cost of the dispute
      uint256 cost = arbitrator.arbitrationCost(arbitratorExtraData);
      require(msg.value >= cost, "Not enough for arbitration");
      uint256 arbitratorDisputeId = arbitrator.createDispute{value: msg.value}(RULING_OPTIONS, arbitratorExtraData);
      claim.arbitratorDisputeId = arbitratorDisputeId;
      claim.status = ClaimStatus.Disputed;
      // timestamp not updated in this path since it has no use anymore
      // metaEvidenceId is 0, evidenceGroupId is the claimId
      emit Dispute(arbitrator, arbitratorDisputeId, 0, _claimId);
    } else {
      claim.timestamp = block.timestamp;
      claim.status = ClaimStatus.CounterOffered;
    }
  }

  // could've inferred the state of the claim and add different requires
  // to check if you're in counter offer properly. but I didn't want to bother,
  // this usage is niche anyway and I want to keep the contract small
  function advanceToCounterOffer(uint256 _claimId) external {
    Claim storage claim = claims[_claimId];
    require(claim.status == ClaimStatus.Claimed, "Must be claimed");
    require(claim.timestamp + counterOfferPeriod < block.timestamp, "Period must have passed");
    claim.status = ClaimStatus.CounterOffered;
    claim.timestamp = block.timestamp;

    emit CounterOffer(_claimId, 0); // for compatibility
  }

  function acceptCounterOffer(uint256 _claimId) external {
    Claim storage claim = claims[_claimId];
    require(msg.sender == claim.claimant, "Only claimant can accept counter offer");
    require(claim.status == ClaimStatus.CounterOffered, "Must be in counterOffered status");
    require(claim.timestamp + challengePeriod >= block.timestamp, "Out of time to accept counterOffer");
    // if a claimant is timed out, consider the claim forfeited. it cannot make progress.

    claim.status = ClaimStatus.Resolved;
    claimUtils.payOutClaim(claim.beneficiary, claim.counterOfferAmount);
    emit ClaimResolved(_claimId, claim.counterOfferAmount);
  }

  /**
   * intended evidence
   * claimant posts why the counter offer is not enough
   * e.g. arguing against the arguments of the insurer
   */
  function challengeCounterOffer(uint256 _claimId, string calldata _evidence) external payable {
    Claim storage claim = claims[_claimId];
    require(msg.sender == claim.claimant, "Only claimant can accept counter offer");
    require(claim.status == ClaimStatus.CounterOffered, "Must be in counterOffered status");
    require(claim.timestamp + challengePeriod >= block.timestamp, "Out of time to challenge");

    uint256 arbitratorDisputeId = arbitrator.createDispute{value: msg.value}(RULING_OPTIONS, arbitratorExtraData);

    disputeIdToClaimId[arbitratorDisputeId] = _claimId;

    claim.status = ClaimStatus.Disputed;
    claim.arbitratorDisputeId = arbitratorDisputeId;
    // metaEvidenceID is always 0. evidenceGroupID is the id of the claim.
    emit Dispute(arbitrator, arbitratorDisputeId, 0, _claimId);
    emit Evidence(arbitrator, _claimId, msg.sender, _evidence);
  }

  // makeshift function to handle appealing logic for now, without contribs
  // anyone can offer themselves to pay for the appeal (e.g. with an external contract)
  function appeal(uint256 _claimId) external payable {
    Claim storage claim = claims[_claimId];
    uint256 appealCost = arbitrator.appealCost(claim.arbitratorDisputeId, arbitratorExtraData);
    require(msg.value >= appealCost, "Not enough to fund appeal");
    arbitrator.appeal(claim.arbitratorDisputeId, arbitratorExtraData);
  }

  function submitEvidence(uint256 _claimId, string calldata _evidence) external {
    emit Evidence(arbitrator, _claimId, msg.sender, _evidence);
  }

  // arbitrator is trusted
  function rule(uint256 _disputeId, uint256 _ruling) external override {
    require(msg.sender == address(arbitrator), "Only arbitrator can rule");
    uint256 claimId = disputeIdToClaimId[_disputeId];
    Claim storage claim = claims[claimId];
    require(claim.status == ClaimStatus.Disputed, "Claim cannot be ruled");
    require(_ruling <= RULING_OPTIONS, "Invalid ruling option");

    claim.status = ClaimStatus.Resolved;
    emit Ruling(arbitrator, _disputeId, _ruling);

    if (_ruling == 0 || _ruling == 1) {
      emit ClaimResolved(claimId, 0);
    } else if (_ruling == 2) {
      emit ClaimResolved(claimId, claim.claimedAmount);
      updateAccumulatedPayouts(uint224(claim.claimedAmount));
      claimUtils.payOutClaim(claim.beneficiary, claim.claimedAmount);
    } else if (_ruling == 3) {
      emit ClaimResolved(claimId, claim.counterOfferAmount);
      updateAccumulatedPayouts(uint224(claim.claimedAmount));
      claimUtils.payOutClaim(claim.beneficiary, claim.counterOfferAmount);
    }
  }
}
