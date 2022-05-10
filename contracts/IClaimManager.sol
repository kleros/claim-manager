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
  event ClaimCreated(uint256 _claimId, uint256 _claimedAmount, bytes32 _policyHash);
  event CounterOffer(uint256 _claimId, uint256 _counterOfferAmount);
  event ClaimResolved(uint256 _claimId, uint256 _settlement);
  event CreatedPolicy(
    bytes32 indexed policyHash,
    address claimant,
    address beneficiary,
    uint256 coverage,
    uint256 endTime,
    string documentIpfsCidV1
  );

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

  function createPolicy(
    address _claimant,
    address _beneficiary,
    uint256 _coverage,
    uint256 _endTime,
    string calldata _documentIpfsCidV1
  ) external returns (bytes32 policyHash);

  function changeInsurer(address _insurer) external;
}
