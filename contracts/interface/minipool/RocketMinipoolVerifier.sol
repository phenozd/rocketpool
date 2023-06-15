pragma solidity >0.5.0 <0.9.0;
pragma abicoder v2;

import "../../types/StakeProof.sol";
import "../../types/PromotionProof.sol";

// SPDX-License-Identifier: GPL-3.0-only

interface RocketMinipoolVerifierInterface {
    function verifyStake(address _minipoolAddress, bytes calldata _pubkey, StakeProof calldata _proof) external view returns (bool);
    function verifyPromotion(address _minipoolAddress, bytes calldata _pubkey, PromotionProof calldata _proof) external view returns (bool);
}
