import { printTitle } from '../_utils/formatting';
import { shouldRevert } from '../_utils/testing';
import { userDeposit } from '../_helpers/deposit';
import { createMinipool, getMinipoolMinimumRPLStake } from '../_helpers/minipool';
import { submitBalances } from '../_helpers/network';
import { registerNode, setNodeTrusted, nodeDeposit, nodeStakeRPL } from '../_helpers/node';
import { getRethExchangeRate, getRethTotalSupply, mintRPL } from '../_helpers/tokens';
import { getDepositSetting } from '../_helpers/settings';
import { deposit } from '../deposit/scenario-deposit';
import {
    RocketDAONodeTrustedSettingsMembers,
    RocketDAOProtocolSettingsDeposit, RocketDepositPool,
} from '../_utils/artifacts';
import { setDAOProtocolBootstrapSetting } from '../dao/scenario-dao-protocol-bootstrap';
import { setDAONodeTrustedBootstrapSetting } from '../dao/scenario-dao-node-trusted-bootstrap'
import { assignDepositsV2 } from '../deposit/scenario-assign-deposits-v2';
import { assertBN } from '../_helpers/bn';

export default function() {
    contract('RocketDepositPool', async (accounts) => {


        // Accounts
        const [
            owner,
            node,
            trustedNode,
            staker,
            random,
        ] = accounts;


        // Setup
        before(async () => {
            // Register node
            await registerNode({from: node});

            // Register trusted node
            await registerNode({from: trustedNode});
            await setNodeTrusted(trustedNode, 'saas_1', 'node@home.com', owner);
        });


        describe(printTitle('staker','cannot make a deposit while deposits are disabled'), function() {
            let depositAmount = '10'.ether;
            it('Given that a staker tries to deposit while deposits are disabled', async function() {
                await setDAOProtocolBootstrapSetting(RocketDAOProtocolSettingsDeposit, 'deposit.enabled', false, {from: owner});
            }),
          
            it('Then the transaction should revert', async function() {
                await shouldRevert(deposit({
                    from: staker,
                    value: depositAmount,
                }), 'Made a deposit while deposits are disabled');
            })
        });

        describe(printTitle('staker','cannot make a deposit below the minimum deposit amount'), function() {
            var minimumDeposit;
            var depositAmount;
            before(async function () {
                minimumDeposit = await getDepositSetting('MinimumDeposit');
                depositAmount = minimumDeposit.div('2'.BN);
            });
            it('Given that a staker tries to deposit below the minimum deposit amount', async function() {
                assertBN.isBelow(depositAmount, minimumDeposit, 'Deposit amount is not less than the minimum deposit');
            }),
          
            it('Then the transaction should revert', async function() {
                await shouldRevert(deposit({
                    from: staker,
                    value: depositAmount,
                }), 'Made a deposit below the minimum deposit amount');
            })
        });

        describe(printTitle('staker','cannot make a deposit which would exceed the maximum deposit pool size'), function() {
            let depositAmount = '100'.ether;
            let exceedAmount = '101'.ether;
            it('Given that a staker tries to deposit more than the maximum deposit pool size', async function() {
                    // Set max deposit pool size
                await setDAOProtocolBootstrapSetting(RocketDAOProtocolSettingsDeposit, 'deposit.pool.maximum', depositAmount, {from: owner});
            }),
          
            it('Then the transaction should revert', async function() {
                await shouldRevert(deposit({
                    from: staker,
                    value: exceedAmount,
                }), 'Made a deposit which exceeds the maximum deposit pool size');
            })
        });

    });
}
