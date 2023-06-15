import { ethers } from 'ethers';

export function generateBeaconStateProofForStake(validatorPubkey, withdrawalCredentials, validatorIndex) {
    // Construct the pubkey/withdrawal credentials leaf node
    const pubkey = validatorPubkey.substring(2)
    const pubkeyHash = ethers.utils.sha256(ethers.utils.defaultAbiCoder.encode(['bytes32', 'bytes32'], ["0x" + pubkey.substring(0, 64), "0x" + pubkey.substring(64).padEnd(64, '0')]))
    const parent = ethers.utils.sha256(ethers.utils.defaultAbiCoder.encode(['bytes32', 'bytes32'], [pubkeyHash, withdrawalCredentials]));

    // Build a gindex that points to the pubkey/withdrawal credentials leaf
    const gindex = '010110' + validatorIndex.toString().padStart(40, '0') + '00'

    // Compute a root where all the other leaves are zeros
    const zero = "0x0000000000000000000000000000000000000000000000000000000000000000"
    let witnesses = [];
    let root = parent;
    for (let i = gindex.length - 1; i >- 0; i--) {
        witnesses.push(zero);
        let values
        if (gindex[i] === '0') {
            values = [root, zero]
        } else {
            values = [zero, root]
        }
        root = ethers.utils.sha256(ethers.utils.defaultAbiCoder.encode(['bytes32', 'bytes32'], values));
    }

    return {
        beaconStateRoot: root,
        validatorIndex: validatorIndex,
        proof: witnesses
    }
}

export function generateBeaconStateProofForPromotion(validatorPubkey, withdrawalCredentials, effectiveBalance, validatorIndex) {
    // Construct the pubkey/withdrawal credentials leaf node
    const pubkey = validatorPubkey.substring(2)
    const pubkeyHash = ethers.utils.sha256(ethers.utils.defaultAbiCoder.encode(['bytes32', 'bytes32'], ["0x" + pubkey.substring(0, 64), "0x" + pubkey.substring(64).padEnd(64, '0')]))
    const leafA = ethers.utils.sha256(ethers.utils.defaultAbiCoder.encode(['bytes32', 'bytes32'], [pubkeyHash, withdrawalCredentials]));
    const leafB = ethers.utils.sha256(ethers.utils.defaultAbiCoder.encode(['bytes32', 'bytes32'], [u64ToLE256(effectiveBalance), "0x0000000000000000000000000000000000000000000000000000000000000000"]));
    const parent = ethers.utils.sha256(ethers.utils.defaultAbiCoder.encode(['bytes32', 'bytes32'], [leafA, leafB]));

    // Build a gindex that points to the parent leaf
    const gindex = '010110' + validatorIndex.toString().padStart(40, '0') + '0'

    // Compute a root where all the other leaves are zeros
    const zero = "0x0000000000000000000000000000000000000000000000000000000000000000"
    let witnesses = [];
    let root = parent;
    for (let i = gindex.length - 1; i >- 0; i--) {
        witnesses.push(zero);
        let values
        if (gindex[i] === '0') {
            values = [root, zero]
        } else {
            values = [zero, root]
        }
        root = ethers.utils.sha256(ethers.utils.defaultAbiCoder.encode(['bytes32', 'bytes32'], values));
    }

    return {
        beaconStateRoot: root,
        validatorIndex: validatorIndex,
        effectiveBalance: '0x' + effectiveBalance.toString(16),
        proof: witnesses
    }
}

function u64ToLE256(value) {
    let valStr = value.toString(16);
    let retStr = '';

    if (valStr.length % 2 === 1) {
        valStr = '0' + valStr;
    }

    for (let i = valStr.length-2; i >= 0; i -= 2) {
        retStr += valStr[i] + valStr[i+1];
    }

    return '0x' + retStr.padEnd(64, '0')
}