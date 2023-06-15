pragma solidity >0.5.0 <0.9.0;

struct StakeProof {
    bytes32 beaconStateRoot;
    uint64 validatorIndex;
    bytes32[] proof;
}
