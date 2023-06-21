// const shouldRevert = require('../_utils/testing');
// const {registerNode, setNodeTrusted, nodeDeposit, nodeStakeRPL} = require('../_helpers/node');
// const getDepositSetting = require('../_helpers/settings');
// const deposit = require('../deposit/scenario-deposit');
// const assertBN = require('../_helpers/bn');
import { printTitle } from '../_utils/formatting.js';
import { shouldRevert } from '../_utils/testing.js';
import { userDeposit } from '../_helpers/deposit.js';
import { createMinipool, getMinipoolMinimumRPLStake } from '../_helpers/minipool.js';
import { submitBalances } from '../_helpers/network.js';
import { registerNode, setNodeTrusted, nodeDeposit, nodeStakeRPL } from '../_helpers/node.js';
import { getRethExchangeRate, getRethTotalSupply, mintRPL } from '../_helpers/tokens.js';
import { getDepositSetting } from '../_helpers/settings.js';
import { deposit } from '../deposit/scenario-deposit.js';
import {
    RocketDAONodeTrustedSettingsMembers,
    RocketDAOProtocolSettingsDeposit, RocketDepositPool,
} from '../_utils/artifacts.js';
import { setDAOProtocolBootstrapSetting } from '../dao/scenario-dao-protocol-bootstrap.js';
import { setDAONodeTrustedBootstrapSetting } from '../dao/scenario-dao-node-trusted-bootstrap.js'
import { assignDepositsV2 } from '../deposit/scenario-assign-deposits-v2.js';
import { assertBN } from '../_helpers/bn.js';

import { Given, When, Then } from '@cucumber/cucumber';

Then('staker cannot make a deposit below the minimum value', async function () {
    // Write code here that turns the phrase above into concrete actions
    return 'pending';
  });

// export default function() {
//   contract('RocketDepositPool', async (accounts) => {

//       // Accounts
//       const [
//           owner,
//           node,
//           trustedNode,
//           staker,
//           random,
//       ] = accounts;


//       // Setup
//       before(async () => {
//           // Register node
//           await registerNode({from: node});

//           // Register trusted node
//           await registerNode({from: trustedNode});
//           await setNodeTrusted(trustedNode, 'saas_1', 'node@home.com', owner);
//       });


//       Given('staker cannot make a deposit below the minimum value', async function () {
//           // Get & check deposit amount
//           let minimumDeposit = await getDepositSetting('MinimumDeposit');
//           let depositAmount = minimumDeposit.div('2'.BN);
//           assertBN.isBelow(depositAmount, minimumDeposit, 'Deposit amount is not less than the minimum deposit');

//           // Attempt deposit
//           await shouldRevert(deposit({
//               from: staker,
//               value: depositAmount,
//           }), 'Made a deposit below the minimum deposit amount');
//       });

//   });
// }

