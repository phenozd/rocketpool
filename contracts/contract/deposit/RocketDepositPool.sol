pragma solidity 0.7.6;

// SPDX-License-Identifier: GPL-3.0-only

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../RocketBase.sol";
import "../../interface/RocketVaultInterface.sol";
import "../../interface/RocketVaultWithdrawerInterface.sol";
import "../../interface/deposit/RocketDepositPoolInterface.sol";
import "../../interface/minipool/RocketMinipoolInterface.sol";
import "../../interface/minipool/RocketMinipoolQueueInterface.sol";
import "../../interface/dao/protocol/settings/RocketDAOProtocolSettingsDepositInterface.sol";
import "../../interface/dao/protocol/settings/RocketDAOProtocolSettingsMinipoolInterface.sol";
import "../../interface/dao/protocol/settings/RocketDAOProtocolSettingsNetworkInterface.sol";
import "../../interface/token/RocketTokenRETHInterface.sol";
import "../../types/MinipoolDeposit.sol";

// The main entry point for deposits into the RP network
// Accepts user deposits and mints rETH; handles assignment of deposited ETH to minipools

contract RocketDepositPool is RocketBase, RocketDepositPoolInterface, RocketVaultWithdrawerInterface {

    // Libs
    using SafeMath for uint;

    // Events
    event DepositReceived(address indexed from, uint256 amount, uint256 time);
    event DepositRecycled(address indexed from, uint256 amount, uint256 time);
    event DepositAssigned(address indexed minipool, uint256 amount, uint256 time);
    event ExcessWithdrawn(address indexed to, uint256 amount, uint256 time);


    // Structs
    struct MinipoolAssignment {
        address minipoolAddress;
        uint256 etherAssigned;
    }

    // Modifiers
    modifier onlyThisLatestContract() {
        // Compiler can optimise out this keccak at compile time
        require(address(this) == getAddress(keccak256("contract.addressrocketDepositPool")), "Invalid or outdated contract");
        _;
    }

    // Construct
    constructor(RocketStorageInterface _rocketStorageAddress) RocketBase(_rocketStorageAddress) {
        version = 3;
    }

    // Returns the amount of the deposit pool that was contributed by the minipool queue
    function getNodeBalance() private view returns (uint256) {
        return getUint("deposit.pool.node.balance");
    }

    // Current deposit pool balance
    function getBalance() override public view returns (uint256) {
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress("rocketVault"));
        return rocketVault.balanceOf("rocketDepositPool").sub(getNodeBalance());
    }

    // Excess deposit pool balance (in excess of minipool queue capacity)
    function getExcessBalance() override public view returns (uint256) {
        // Get minipool queue capacity
        RocketMinipoolQueueInterface rocketMinipoolQueue = RocketMinipoolQueueInterface(getContractAddress("rocketMinipoolQueue"));
        uint256 minipoolCapacity = rocketMinipoolQueue.getEffectiveCapacity();
        // Calculate and return
        uint256 balance = getBalance();
        if (minipoolCapacity >= balance) { return 0; }
        else { return balance.sub(minipoolCapacity); }
    }

    // Receive a vault withdrawal
    // Only accepts calls from the RocketVault contract
    function receiveVaultWithdrawalETH() override external payable onlyThisLatestContract onlyLatestContract("rocketVault", msg.sender) {}

    // Accept a deposit from a user
    function deposit() override external payable onlyThisLatestContract {
        // Check deposit settings
        RocketDAOProtocolSettingsDepositInterface rocketDAOProtocolSettingsDeposit = RocketDAOProtocolSettingsDepositInterface(getContractAddress("rocketDAOProtocolSettingsDeposit"));
        require(rocketDAOProtocolSettingsDeposit.getDepositEnabled(), "Deposits into Rocket Pool are currently disabled");
        require(msg.value >= rocketDAOProtocolSettingsDeposit.getMinimumDeposit(), "The deposited amount is less than the minimum deposit size");
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress("rocketVault"));
        uint256 capacityNeeded = rocketVault.balanceOf("rocketDepositPool").add(msg.value);
        if (capacityNeeded > rocketDAOProtocolSettingsDeposit.getMaximumDepositPoolSize()) {
            // Doing a conditional require() instead of a single one optimizes for the common
            // case where capacityNeeded fits in the deposit pool without looking at the queue
            if (rocketDAOProtocolSettingsDeposit.getAssignDepositsEnabled()) {
                RocketMinipoolQueueInterface rocketMinipoolQueue = RocketMinipoolQueueInterface(getContractAddress("rocketMinipoolQueue"));
                require(capacityNeeded <= rocketDAOProtocolSettingsDeposit.getMaximumDepositPoolSize() + rocketMinipoolQueue.getEffectiveCapacity(),
                    "The deposit pool size after depositing (and matching with minipools) exceeds the maximum size");
            } else {
                revert("The deposit pool size after depositing exceeds the maximum size");
            }
        }

        // Calculate deposit fee
        uint256 depositFee = msg.value.mul(rocketDAOProtocolSettingsDeposit.getDepositFee()).div(calcBase);
        uint256 depositNet = msg.value.sub(depositFee);
        // Mint rETH to user account
        RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(getContractAddress("rocketTokenRETH"));
        rocketTokenRETH.mint(depositNet, msg.sender);
        // Emit deposit received event
        emit DepositReceived(msg.sender, msg.value, block.timestamp);
        // Process deposit
        processDeposit(rocketVault, rocketDAOProtocolSettingsDeposit);
    }

    // Accepts ETH deposit from the node deposit contract (does not mint rETH)
    function nodeDeposit() override external payable onlyThisLatestContract onlyLatestContract("rocketNodeDeposit", msg.sender) {
        // Deposit ETH into the vault
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress("rocketVault"));
        rocketVault.depositEther{value: msg.value}();
        // Increase recorded node balance
        addUint("deposit.pool.node.balance", msg.value);
    }

    // Recycle a deposit from a dissolved minipool
    // Only accepts calls from registered minipools
    function recycleDissolvedDeposit() override external payable onlyThisLatestContract onlyRegisteredMinipool(msg.sender) {
        // Load contracts
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress("rocketVault"));
        RocketDAOProtocolSettingsDepositInterface rocketDAOProtocolSettingsDeposit = RocketDAOProtocolSettingsDepositInterface(getContractAddress("rocketDAOProtocolSettingsDeposit"));
        // Recycle ETH
        emit DepositRecycled(msg.sender, msg.value, block.timestamp);
        processDeposit(rocketVault, rocketDAOProtocolSettingsDeposit);
    }

    // Recycle excess ETH from the rETH token contract
    function recycleExcessCollateral() override external payable onlyThisLatestContract onlyLatestContract("rocketTokenRETH", msg.sender) {
        // Load contracts
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress("rocketVault"));
        RocketDAOProtocolSettingsDepositInterface rocketDAOProtocolSettingsDeposit = RocketDAOProtocolSettingsDepositInterface(getContractAddress("rocketDAOProtocolSettingsDeposit"));
        // Recycle ETH
        emit DepositRecycled(msg.sender, msg.value, block.timestamp);
        processDeposit(rocketVault, rocketDAOProtocolSettingsDeposit);
    }

    // Recycle a liquidated RPL stake from a slashed minipool
    // Only accepts calls from the RocketAuctionManager contract
    function recycleLiquidatedStake() override external payable onlyThisLatestContract onlyLatestContract("rocketAuctionManager", msg.sender) {
        // Load contracts
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress("rocketVault"));
        RocketDAOProtocolSettingsDepositInterface rocketDAOProtocolSettingsDeposit = RocketDAOProtocolSettingsDepositInterface(getContractAddress("rocketDAOProtocolSettingsDeposit"));
        // Recycle ETH
        emit DepositRecycled(msg.sender, msg.value, block.timestamp);
        processDeposit(rocketVault, rocketDAOProtocolSettingsDeposit);
    }

    // Process a deposit
    function processDeposit(RocketVaultInterface _rocketVault, RocketDAOProtocolSettingsDepositInterface _rocketDAOProtocolSettingsDeposit) private {
        // Transfer ETH to vault
        _rocketVault.depositEther{value: msg.value}();
        // Assign deposits if enabled
        _assignDeposits(_rocketVault, _rocketDAOProtocolSettingsDeposit);
    }

    // Assign deposits to available minipools
    function assignDeposits() override external onlyThisLatestContract {
        // Load contracts
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress("rocketVault"));
        RocketDAOProtocolSettingsDepositInterface rocketDAOProtocolSettingsDeposit = RocketDAOProtocolSettingsDepositInterface(getContractAddress("rocketDAOProtocolSettingsDeposit"));
        // Revert if assigning is disabled
        require(_assignDeposits(rocketVault, rocketDAOProtocolSettingsDeposit), "Deposit assignments are currently disabled");
    }

    // Assigns deposits to available minipools, returns false if assignment is currently disabled
    function _assignDeposits(RocketVaultInterface _rocketVault, RocketDAOProtocolSettingsDepositInterface _rocketDAOProtocolSettingsDeposit) private returns (bool) {
        // Check if assigning deposits is enabled
        if (!_rocketDAOProtocolSettingsDeposit.getAssignDepositsEnabled()) {
            return false;
        }
        // Load contracts
        RocketMinipoolQueueInterface rocketMinipoolQueue = RocketMinipoolQueueInterface(getContractAddress("rocketMinipoolQueue"));
        // Decide which queue processing implementation to use based on queue contents
        if (rocketMinipoolQueue.getContainsLegacy()) {
            return _assignDepositsLegacy(rocketMinipoolQueue, _rocketVault, _rocketDAOProtocolSettingsDeposit);
        } else {
            return _assignDepositsNew(rocketMinipoolQueue, _rocketVault, _rocketDAOProtocolSettingsDeposit);
        }
    }

    function _assignDepositsNew(RocketMinipoolQueueInterface _rocketMinipoolQueue, RocketVaultInterface _rocketVault, RocketDAOProtocolSettingsDepositInterface _rocketDAOProtocolSettingsDeposit) private returns (bool) {
        // Load contracts
        RocketDAOProtocolSettingsMinipoolInterface rocketDAOProtocolSettingsMinipool = RocketDAOProtocolSettingsMinipoolInterface(getContractAddress("rocketDAOProtocolSettingsMinipool"));
        // Calculate the number of minipools to assign
        uint256 maxAssignments = _rocketDAOProtocolSettingsDeposit.getMaximumDepositAssignments();
        uint256 variableDepositAmount = rocketDAOProtocolSettingsMinipool.getVariableDepositAmount();
        uint256 scalingCount = msg.value.div(variableDepositAmount);
        uint256 totalEthCount = _rocketVault.balanceOf("rocketDepositPool").div(variableDepositAmount);
        uint256 assignments = _rocketDAOProtocolSettingsDeposit.getMaximumDepositSocialisedAssignments().add(scalingCount);
        if (assignments > totalEthCount) {
            assignments = totalEthCount;
        }
        if (assignments > maxAssignments) {
            assignments = maxAssignments;
        }
        address[] memory minipools = _rocketMinipoolQueue.dequeueMinipools(assignments);
        if (minipools.length > 0){
            // Withdraw ETH from vault
            uint256 totalEther = minipools.length.mul(variableDepositAmount);
            _rocketVault.withdrawEther(totalEther);
            // Loop over minipools and deposit the amount required to reach launch balance
            uint256 nodeBalanceReduction = 0;
            for (uint256 i = 0; i < minipools.length; i++) {
                RocketMinipoolInterface minipool = RocketMinipoolInterface(minipools[i]);
                // Calculate the reduction in node balance from this minipool
                nodeBalanceReduction = nodeBalanceReduction.add(minipool.getNodeTopUpValue());
                // Assign deposit to minipool
                minipool.deposit{value: variableDepositAmount}();
                // Emit deposit assigned event
                emit DepositAssigned(minipools[i], variableDepositAmount, block.timestamp);
            }
            // Decrease node balance
            subUint("deposit.pool.node.balance", nodeBalanceReduction);
        }
        return true;
    }

    function _assignDepositsLegacy(RocketMinipoolQueueInterface _rocketMinipoolQueue, RocketVaultInterface _rocketVault, RocketDAOProtocolSettingsDepositInterface _rocketDAOProtocolSettingsDeposit) private returns (bool) {
        // Load contracts
        RocketDAOProtocolSettingsMinipoolInterface rocketDAOProtocolSettingsMinipool = RocketDAOProtocolSettingsMinipoolInterface(getContractAddress("rocketDAOProtocolSettingsMinipool"));
        // Setup initial variable values
        uint256 balance = _rocketVault.balanceOf("rocketDepositPool");
        uint256 totalEther = 0;
        // Calculate minipool assignments
        uint256 maxAssignments = _rocketDAOProtocolSettingsDeposit.getMaximumDepositAssignments();
        MinipoolAssignment[] memory assignments = new MinipoolAssignment[](maxAssignments);
        MinipoolDeposit depositType = MinipoolDeposit.None;
        uint256 count = 0;
        uint256 minipoolCapacity = 0;
        for (uint256 i = 0; i < maxAssignments; ++i) {
            // Optimised for multiple of the same deposit type
            if (count == 0) {
                (depositType, count) = _rocketMinipoolQueue.getNextDepositLegacy();
                if (depositType == MinipoolDeposit.None) { break; }
                minipoolCapacity = rocketDAOProtocolSettingsMinipool.getDepositUserAmount(depositType);
            }
            count--;
            if (minipoolCapacity == 0 || balance.sub(totalEther) < minipoolCapacity) { break; }
            // Dequeue the minipool
            address minipoolAddress = _rocketMinipoolQueue.dequeueMinipoolByDepositLegacy(depositType);
            // Update running total
            totalEther = totalEther.add(minipoolCapacity);
            // Add assignment
            assignments[i].etherAssigned = minipoolCapacity;
            assignments[i].minipoolAddress = minipoolAddress;
        }
        if (totalEther > 0) {
            // Withdraw ETH from vault
            _rocketVault.withdrawEther(totalEther);
            // Perform assignments
            for (uint256 i = 0; i < maxAssignments; ++i) {
                if (assignments[i].etherAssigned == 0) { break; }
                RocketMinipoolInterface minipool = RocketMinipoolInterface(assignments[i].minipoolAddress);
                // Assign deposit to minipool
                minipool.userDeposit{value: assignments[i].etherAssigned}();
                // Emit deposit assigned event
                emit DepositAssigned(assignments[i].minipoolAddress, assignments[i].etherAssigned, block.timestamp);
            }
        }
        return true;
    }

    // Withdraw excess deposit pool balance for rETH collateral
    function withdrawExcessBalance(uint256 _amount) override external onlyThisLatestContract onlyLatestContract("rocketTokenRETH", msg.sender) {
        // Load contracts
        RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(getContractAddress("rocketTokenRETH"));
        RocketVaultInterface rocketVault = RocketVaultInterface(getContractAddress("rocketVault"));
        // Check amount
        require(_amount <= getExcessBalance(), "Insufficient excess balance for withdrawal");
        // Withdraw ETH from vault
        rocketVault.withdrawEther(_amount);
        // Transfer to rETH contract
        rocketTokenRETH.depositExcess{value: _amount}();
        // Emit excess withdrawn event
        emit ExcessWithdrawn(msg.sender, _amount, block.timestamp);
    }
}
