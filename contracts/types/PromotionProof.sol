pragma solidity >0.5.0 <0.9.0;

struct PromotionProof {
    bytes32 beaconStateRoot;
    uint64 validatorIndex;
    bytes32[] proof;
    uint64 effectiveBalance;
}
