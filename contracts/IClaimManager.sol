/**
 * @authors: [@greenlucid]
 * @reviewers: []
 * @auditors: []
 * @bounties: []
 * @deployments: []
 * SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.12;

// interface for insurer or claimant multisigs

interface IClaimManager {
  event ClaimCreated(uint256 _claimedAmount);
  event CounterOffer(uint256 _claimId, uint256 _counterOfferAmount);
  event ClaimResolved(uint256 _claimId, uint256 _settlement);

  function claimInsurance(
    address _beneficiary,
    uint256 _coverage,
    uint256 _endTime,
    string calldata _documentIpfsCidV1,
    uint256 _claimedAmount,
    string calldata _evidence
    ) external;

  function acceptClaim(uint256 _claimId) external;

  function counterOffer(uint256 _claimId, uint256 _amount, bool _toDispute, string calldata _evidence)
    external payable;

  function acceptCounterOffer(uint256 _claimId) external;

  function challengeCounterOffer(uint256 _claimId, string calldata _evidence) external payable;

  function submitEvidence(uint256 _claimId, string calldata _evidence) external;
}