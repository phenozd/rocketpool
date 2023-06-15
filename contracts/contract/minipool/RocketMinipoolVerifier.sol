pragma solidity 0.8.19;

// SPDX-License-Identifier: GPL-3.0-only

import "../RocketBase.sol";
import "../../interface/minipool/RocketMinipoolVerifier.sol";
import "../../types/StakeProof.sol";

/// @notice Handles verification of beacon state proofs for withdrawal credentials on new minipools
contract RocketMinipoolVerifier is RocketBase, RocketMinipoolVerifierInterface {

    // In production, this would use the precompile being added by EIP-4388 instead
    mapping(address => bool) oracles;
    mapping(bytes32 => bool) beaconStateRoots;

    // Construct
    constructor(RocketStorageInterface _rocketStorageAddress) RocketBase(_rocketStorageAddress) {
        version = 1;
    }

    /// @notice Verifies that a given stake proof is valid
    function verifyStake(address _minipoolAddress, bytes calldata _pubkey, StakeProof calldata _proof) external override view returns (bool) {
        require(_proof.validatorIndex < 2 ** 40, "Invalid validator index");

        // Verify the provided state root is a legitimate one
        // TODO: with EIP-4788 we get the block timestamp of a state root for free so we could limit this to recent proofs if desired
        if (!beaconStateRoots[_proof.beaconStateRoot]) {
            return false;
        }

        // Calculate the pubkey/withdrawal credentials node and the gid for it
        bytes32 leaf = sha256(abi.encodePacked(merkelisePubkey(_pubkey), getMinipoolWithdrawalCredentials(_minipoolAddress)));
        uint256 gid = ((((2 ** beaconObjectDepth) + validatorsIndex) << (validatorsDepth + 1)) + _proof.validatorIndex) << (validatorObjectDepth-1);

        // Verify
        return verify(_proof.proof, _proof.beaconStateRoot, leaf, gid);
    }

    /// @notice Verifies that a given promotion proof is valid
    function verifyPromotion(address _minipoolAddress, bytes calldata _pubkey, PromotionProof calldata _proof) external override view returns (bool) {
        require(_proof.validatorIndex < 2 ** 40, "Invalid validator index");

        // Verify the provided state root is a legitimate one
        // TODO: with EIP-4788 we get the block timestamp of a state root for free so we could limit this to recent proofs if desired
        if (!beaconStateRoots[_proof.beaconStateRoot]) {
            return false;
        }

        // Calculate the pubkey/withdrawal credentials node
        bytes32 leafA = sha256(abi.encodePacked(merkelisePubkey(_pubkey), getMinipoolWithdrawalCredentials(_minipoolAddress)));

        // Calculate the effective balance/slashed node
        bytes32 leafB = sha256(abi.encodePacked(u64ToLE256(_proof.effectiveBalance), boolToLE256(false)));

        // Calculate the parent node and GID
        bytes32 leaf = sha256(abi.encodePacked(leafA, leafB));
        uint256 gid = ((((2 ** beaconObjectDepth) + validatorsIndex) << (validatorsDepth + 1)) + _proof.validatorIndex) << (validatorObjectDepth-2);

        // Verify
        return verify(_proof.proof, _proof.beaconStateRoot, leaf, gid);
    }

    /// @notice Returns the correct withdrawal credentials for a given minipool
    function getMinipoolWithdrawalCredentials(address _minipoolAddress) internal pure returns (bytes32) {
        return bytes32(abi.encodePacked(bytes1(0x01), bytes11(0x0), address(_minipoolAddress)));
    }

    /// @notice Whitelists a given address to be able to set the mock beacon state root
    /// @param _oracleAddress The address of the oracle to add
    function addOracle(address _oracleAddress) external onlyGuardian {
        oracles[_oracleAddress] = true;
    }

    /// @notice Can be called by oracles to set the mock beacon state root
    /// @param _beaconStateRoot The value to set the mock beacon state root to
    function addBeaconStateRoot(bytes32 _beaconStateRoot) external {
        require(oracles[msg.sender] || msg.sender == rocketStorage.getGuardian(), "Not an oracle");
        beaconStateRoots[_beaconStateRoot] = true;
    }

    /*
    class Validator(Container):
        pubkey: BLSPubkey
        withdrawal_credentials: Bytes32  # Commitment to pubkey for withdrawals
        effective_balance: Gwei  # Balance at stake
        slashed: boolean
        # Status epochs
        activation_eligibility_epoch: Epoch  # When criteria for activation were met
        activation_epoch: Epoch
        exit_epoch: Epoch
        withdrawable_epoch: Epoch  # When validator can withdraw funds
    */
    struct Validator {
        bytes pubkey;
        bytes32 withdrawalCredentials;
        uint64 effectiveBalance;
        bool slashed;
        uint64 activationEligibilityEpoch;
        uint64 activationEpoch;
        uint64 exitEpoch;
        uint64 withdrawableEpoch;
    }

    uint256 constant beaconObjectDepth = 5;          // ceil(log2(21)) = 5
    uint256 constant validatorObjectDepth = 3;       // ceil(log2(8)) = 3
    uint256 constant validatorsDepth = 40;           // Max depth of the validator set (2^40 max validators)
    uint256 constant validatorsIndex = 11;           // validators is the 12th field in the BeaconState object
    uint256 constant pubkeyIndex = 0;                // pubkey is the 1st field in Validator object
    uint256 constant withdrawalCredentialsIndex = 1; // withdrawalCredentials is the 2nd field in Validator object
    uint256 constant balanceIndex = 2;               // balance is the 3rd field in Validator object

    function merkeliseValidator(Validator calldata validator) public pure returns (bytes32) {
        bytes32[6] memory tree;

        bytes32 pubkeyHash = merkelisePubkey(validator.pubkey);

        // Depth 1
        tree[0] = sha256(abi.encodePacked(pubkeyHash, validator.withdrawalCredentials));
        tree[1] = sha256(abi.encodePacked(u64ToLE256(validator.effectiveBalance), boolToLE256(validator.slashed)));
        tree[2] = sha256(abi.encodePacked(u64ToLE256(validator.activationEligibilityEpoch), u64ToLE256(validator.activationEpoch)));
        tree[3] = sha256(abi.encodePacked(u64ToLE256(validator.exitEpoch), u64ToLE256(validator.withdrawableEpoch)));

        // Depth 2
        tree[4] = sha256(abi.encodePacked(tree[0], tree[1]));
        tree[5] = sha256(abi.encodePacked(tree[2], tree[3]));

        // Depth 3
        return sha256(abi.encodePacked(tree[4], tree[5]));
    }

    function merkelisePubkey(bytes calldata pubkey) public pure returns (bytes32) {
        return sha256(abi.encodePacked(bytes32(pubkey[0 : 32]), bytes32(pubkey[32 :])));
    }

    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf, uint256 gindex) internal pure returns (bool) {
        return root == computeRoot(proof, leaf, gindex);
    }

    function computeRoot(bytes32[] memory proof, bytes32 leaf, uint256 gindex) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            bool direction = uint8(gindex >> i) & 0x01 != 0x01;

            if (direction) {
                computedHash = sha256(abi.encodePacked(computedHash, proofElement));
            } else {
                computedHash = sha256(abi.encodePacked(proofElement, computedHash));
            }
        }

        return computedHash;
    }

    function u64ToLE256(uint64 _value) public pure returns (bytes32) {
        bytes8 value = bytes8(_value);
        bytes memory ret = new bytes(32);

        ret[0] = value[7];
        ret[1] = value[6];
        ret[2] = value[5];
        ret[3] = value[4];
        ret[4] = value[3];
        ret[5] = value[2];
        ret[6] = value[1];
        ret[7] = value[0];

        return bytes32(ret);
    }

    function boolToLE256(bool _value) public pure returns (bytes32) {
        return bytes32(uint256(_value ? 1 : 0));
    }
}
