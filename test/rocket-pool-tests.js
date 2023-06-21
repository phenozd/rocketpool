import { printGasUsage, startGasUsage, endGasUsage } from './_utils/gasusage';
import { endSnapShot, injectGlobalSnapShot, startSnapShot } from './_utils/snapshotting';
import { deployRocketPool } from './_helpers/deployment';
import { setDefaultParameters } from './_helpers/defaults';
import { suppressLog } from './_helpers/console';
// Import tests
import auctionTests from './auction/auction-tests';
import depositPoolTests from './deposit/deposit-pool-tests';
import minipoolScrubTests from './minipool/minipool-scrub-tests.js';
import minipoolTests from './minipool/minipool-tests.js';
import minipoolVacantTests from './minipool/minipool-vacant-tests.js';
import minipoolStatusTests from './minipool/minipool-status-tests.js';
import minipoolWithdrawalTests from './minipool/minipool-withdrawal-tests.js';
import networkBalancesTests from './network/network-balances-tests.js';
import networkPenaltiesTests from './network/network-penalties-tests.js';
import networkFeesTests from './network/network-fees-tests.js';
import networkPricesTests from './network/network-prices-tests.js';
import nodeDepositTests from './node/node-deposit-tests.js';
import nodeManagerTests from './node/node-manager-tests.js';
import nodeStakingTests from './node/node-staking-tests.js';
import nodeDistributorTests from './node/node-distributor-tests.js';
import daoProtocolTests from './dao/dao-protocol-tests.js';
import daoNodeTrustedTests from './dao/dao-node-trusted-tests.js';
import rethTests from './token/reth-tests.js';
import rplTests from './token/rpl-tests.js';
import rewardsPoolTests from './rewards/rewards-tests.js';
import { injectBNHelpers } from './_helpers/bn.js';
import { checkInvariants } from './_helpers/invariants.js';

// Header
console.log('\n');
console.log('______           _        _    ______           _ ');
console.log('| ___ \\         | |      | |   | ___ \\         | |');
console.log('| |_/ /___   ___| | _____| |_  | |_/ /__   ___ | |');
console.log('|    // _ \\ / __| |/ / _ \\ __| |  __/ _ \\ / _ \\| |');
console.log('| |\\ \\ (_) | (__|   <  __/ |_  | | | (_) | (_) | |');
console.log('\\_| \\_\\___/ \\___|_|\\_\\___|\\__| \\_|  \\___/ \\___/|_|');

// BN helpers
injectBNHelpers();

// State snapshotting and gas usage tracking
beforeEach(startSnapShot);
beforeEach(startGasUsage);
afterEach(checkInvariants);
afterEach(endGasUsage);
afterEach(endSnapShot);
after(printGasUsage);

before(async function() {
  // Deploy Rocket Pool
  await suppressLog(deployRocketPool);
  // Set starting parameters for all tests
  await setDefaultParameters();
  // Inject a global snapshot before every suite
  injectGlobalSnapShot(this.test.parent)
});

// Run tests
daoProtocolTests();
daoNodeTrustedTests();
auctionTests();
depositPoolTests();
minipoolScrubTests();
minipoolTests();
minipoolVacantTests();
minipoolStatusTests();
minipoolWithdrawalTests();
networkBalancesTests();
networkPenaltiesTests();
networkFeesTests();
networkPricesTests();
nodeDepositTests();
nodeManagerTests();
nodeStakingTests();
nodeDistributorTests();
rethTests();
rplTests();
rewardsPoolTests();
