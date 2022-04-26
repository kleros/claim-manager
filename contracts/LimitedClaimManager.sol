/**
 * @authors: []
 * @reviewers: []
 * @auditors: []
 * @bounties: []
 * @deployments: []
 * SPDX-License-Identifier: MIT
 */

pragma solidity 0.8.12;

import "./ClaimManager.sol";

contract LimitedClaimManager is ClaimManager {
    struct Checkpoint {
        uint256 fromTimestamp;
        uint256 value;
    }
  
    Checkpoint[] public accumulatedPayouts;
    uint256 public immutable claimPayoutLimitPeriod;
    uint256 public immutable claimPayoutLimitAmount;

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
    ) ClaimManager(_claimUtils, _arbitrator, _insurer, _counterOfferPeriod, _challengePeriod, _metaEvidence, _arbitratorExtraData)
    {
        claimPayoutLimitPeriod = _claimPayoutLimitPeriod;
        claimPayoutLimitAmount = _claimPayoutLimitAmount;
        accumulatedPayouts.push(Checkpoint({
            fromTimestamp: block.timestamp,
            value: 0
            }));
    }
  
    function rule(uint256 _disputeId, uint256 _ruling) public virtual override {
      ClaimManager.rule(_disputeId, _ruling);
      if (_ruling == 2) {
        Claim storage claim = claims[disputeIdToClaimId[_disputeId]];
        updateAccumulatedPayouts(claim.claimedAmount);
      } else if (_ruling == 3) {
        Claim storage claim = claims[disputeIdToClaimId[_disputeId]];
        updateAccumulatedPayouts(claim.counterOfferAmount);
      }
    }

    // Call this before paying out
    // It's not implemented as a modifier because it's not cool for modifiers to change state
    function updateAccumulatedPayouts(uint256 payoutAmount) private {
        uint256 accumulatedPayoutsNow = payoutAmount;
        if (accumulatedPayouts.length > 0) {
          accumulatedPayoutsNow += accumulatedPayouts[accumulatedPayouts.length - 1].value;
        }
        accumulatedPayouts.push(Checkpoint({
            fromTimestamp: block.timestamp,
            value: accumulatedPayoutsNow
            }));
        uint256 accumulatedPayoutsThen = getValueAt(accumulatedPayouts, block.timestamp - claimPayoutLimitPeriod);
        require(accumulatedPayoutsNow - accumulatedPayoutsThen <= claimPayoutLimitAmount, "Payout limit exceeded");
    }

    // Adapted from https://github.com/api3dao/api3-dao/blob/c745454d60ad97f6ffa9b5aa612c9a2b7eba16d0/packages/pool/contracts/GetterUtils.sol#L246
    function getValueAt(
        Checkpoint[] storage checkpoints,
        uint256 _timestamp
        )
        private
        view
        returns (uint256)
    {
        if (checkpoints.length == 0)
            return 0;

        // Shortcut for the actual value
        if (_timestamp >= checkpoints[checkpoints.length -1].fromTimestamp)
            return checkpoints[checkpoints.length - 1].value;
        if (_timestamp < checkpoints[0].fromTimestamp)
            return 0;

        // Binary search of the value in the array
        uint min = 0;
        uint max = checkpoints.length - 1;
        while (max > min) {
            uint mid = (max + min + 1) / 2;
            if (checkpoints[mid].fromTimestamp <= _timestamp) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return checkpoints[min].value;
    }
}