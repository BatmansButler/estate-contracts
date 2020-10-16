// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

// endowl.com - Digital Inheritance Automation

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
// Interface generated from @gnosis.pm/safe-contracts/contracts/base/ModuleManager.sol
import "./IModuleManager.sol";

/// @title Digital Inheritance Automation
/// @author endowl.com
contract EndowlEstate  {
    /// @notice Owner of the estate and the assets held within
    address public owner;
    /// @notice Optional trusted party who can assist with estate recover and who takes over managing the estate after confirmation of death
    address public executor;
    /// @notice Optional trusted source of death notifications
    address public oracle;
    /// @notice Optional Gnosis Safe contract used to co-own the estate - receives full ownership permissions
    address public gnosisSafe;

    /// @notice Beneficiaries who may receive shares of assets after confirmation of death and who may assist with estate recovery
    address[] public beneficiaries;
    /// @notice Index of given beneficiary within beneficiaries list
    mapping(address => uint256) public beneficiaryIndex;

    /// @notice Proportional shares of assets assigned  to each beneficiary
    mapping(address => uint256) public beneficiaryShares;
    /// @notice Total number of shares assigned to all beneficiaries
    uint256 public totalShares;

    /// @notice The total known amount of specified tokens held by estate, determined after death for purposes of inheritance
    mapping(address => uint256) public totalTokensKnown;

    /// @notice Has a distribution of the given token to the spcified beneficiary already occurred?
    mapping(address => mapping(address => bool)) public isBeneficiaryTokenWithdrawn;

    // TODO: Further evaluate if precision is sufficient for share ratios
    // precision is used for dividing up shares of assets...
    uint256 private precision = 8**10;

    // address[] public trackedTokens;

    enum Lifesign { Alive, Uncertain, Dead, PlayingDead }

    // Used by Gnosis Safe eg. to perform recovery operation
    enum Operation { Call, DelegateCall }

    /// @notice Estate owner's last known lifesign (0: Alive, 1: Uncertain, 2: Dead, 3: PlayingDead)
    Lifesign public liveness;

    /// @notice If not zero, the timestamp after which the estate owner may be declared dead
    uint256 public declareDeadAfter;
    /// @notice The amount of time after death is reported before it can be confirmed
    uint256 public uncertaintyPeriod = 8 weeks;

    // TODO: Ability to modify uncertaintyPeriod

    // Dead Man's Switch settings
    /// @notice Is the dead man's switch enabled
    bool public isDeadMansSwitchEnabled;
    /// @notice How frequently (in seconds) must the estate owner check-in before the dead man's switch can be triggered
    uint256 public deadMansSwitchCheckinSeconds;
    /// @notice Timestamp of the estate owner's last check-in
    uint256 public deadMansSwitchLastCheckin;

    // Gnosis Safe Recovery settings
    /// @notice Is a signature required from the executor to perform a recovery of the Gnosis Safe?
    bool public isExecutorRequiredForSafeRecovery;
    /// @notice Number of beneficiaries required to perform a recovery the Gnosis Safe
    uint256 public beneficiariesRequiredForSafeRecovery;
    /// @notice Used for Gnosis Safe recovery, has the hashed command been executed?
    mapping (bytes32 => bool) public isExecuted;
    /// @notice Used for Gnosis Safe recovery, has the hashed command been confirmed by the given beneficiary?
    mapping (bytes32 => mapping (address => bool)) public isConfirmed;

    /// @notice The estate owner is simulating death, which is more temporary than actually being dead
    event PlayingDead();
    /// @notice The estate owner is considered to be dead
    event ConfirmationOfDeath();
    /// @notice A report of the estate owner's death has been received from a trusted source
    event ReportOfDeath(address indexed reporter);
    /// @notice The estate owner has been confirmed to be alive
    event ConfirmationOfLife(address indexed reporter);

    /// @notice Ownership of the estate as been transfered to a new address
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    /// @notice Address of the Gnosis Safe has changed
    event GnosisSafeChanged(address indexed gnosisSafe, address indexed newSafe);
    /// @notice Address of the Oracle has changed
    event OracleChanged(address indexed oldOracle, address indexed newOracle);
    /// @notice Address of the Executor has changed
    event ExecutorChanged(address indexed oldExecutor, address indexed newExecutor);
    /// @notice A beneficiary has been added
    event AddedBeneficiary(address indexed newBeneficiary, uint256 indexed shares);
    /// @notice A beneficiary has been removed
    event RemovedBeneficiary(address indexed formerBeneficiary, uint256 indexed removedShares);
    /// @notice The shares assigned to a beneficiary have been modified
    event ChangedBeneficiaryShares(address indexed beneficiary, uint256 indexed oldShares, uint256 indexed newShares);
    /// @notice The address of a beneficiary has been modified
    event ChangedBeneficiaryAddress(address indexed oldAddress, address indexed newAddress);
    /// @notice A beneficiary has withdrawn their shares of a given asset
    event BeneficiaryWithdrawal(address indexed beneficiary, address indexed token, uint256 indexed amount);
    /// @notice Requirement of Executor signature to recover Gnosis Safe has been modified
    event IsExecutorRequiredForSafeRecoveryChanged(bool indexed newValue);
    /// @notice Number of beneficiary signatures required to recover Gnosis Safe has been modified
    event BeneficiariesRequiredForSafeRecoveryChanged(uint256 indexed newValue);
    /// @notice Dead Man's Switch has been enabled or disabled
    event IsDeadMansSwitchEnabledChanged(bool indexed newValue);
    /// @notice Dead Man's Switch timer has been modified
    event DeadMansSwitchCheckinSecondsChanged(uint256 indexed newValue);

    // event TrackedTokenAdded(address indexed token);
    // event TrackedTokenRemoved(address indexed token);

    /// @notice Initialize new estate to be owned by the caller
    constructor() {
        // Set the caller as the estate owner
        owner = msg.sender;
        // Set the estate owner as alive
        liveness = Lifesign.Alive;

        // To support recovery of the Gnosis Safe (if one gets assigned), this contract will need to be set as that safe's recovery manager
        // Set defaults for recovering a Gnosis Safe to require at least two very trusted parties
        isExecutorRequiredForSafeRecovery = true;
        beneficiariesRequiredForSafeRecovery = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner || msg.sender == gnosisSafe, "Caller is not the owner");
        require(liveness != Lifesign.Dead, "Owner is no longer alive");
        _;
    }

    modifier onlyExecutor() {
        require(msg.sender == executor, "Caller is not the executor");
        _;
    }

    modifier onlyOwnerOrExecutor() {
        require(msg.sender == owner || msg.sender == gnosisSafe || msg.sender == executor, "Caller is not the owner or executor");
        _;
    }

    modifier onlyController() {
        if(liveness == Lifesign.PlayingDead) {
            // The owner is simulating death
            require(msg.sender == owner || msg.sender == gnosisSafe || msg.sender == executor, "Caller is not the owner or executor and the owner is simulating death");
        } else if(liveness != Lifesign.Dead) {
            // The owner is not dead or simulating death
            require(msg.sender == owner || msg.sender == gnosisSafe, "Caller is not the owner and the owner is still alive");
        } else {
            // The owner is dead
            require(msg.sender == executor, "Caller is not the executor and the owner is no longer alive");
        }
        _;
    }

    modifier onlyControllerOrBeneficiary(address who) {
        if(msg.sender == who) {
            require(beneficiaryIndex[who] > 0, "Address is not a registered beneficiary");
        } else {
            if(liveness == Lifesign.PlayingDead) {
                // The owner is simulating death
                require(msg.sender == owner || msg.sender == gnosisSafe || msg.sender == executor, "Caller is not the beneficiary, owner, or executor and the owner is simulating death");
            } else if(liveness != Lifesign.Dead) {
                // The owner is not dead or simulating death
                require(msg.sender == owner || msg.sender == gnosisSafe, "Caller is not the beneficiary or the owner and the owner is still alive");
            } else {
                // The owner is dead
                require(msg.sender == executor, "Caller is not the beneficiary or the executor and the owner is no longer alive");
            }
        }
        _;
    }

    modifier onlyBeneficiary() {
        require(beneficiaryIndex[msg.sender] > 0, "Caller is not a registered beneficiary");
        _;
    }

    modifier onlyMember() {
        require(msg.sender == owner || msg.sender == gnosisSafe || msg.sender == executor || beneficiaryIndex[msg.sender] > 0, "Caller is not a member");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle, "Caller is not the oracle");
        _;
    }

    modifier notUncertain() {
        require(liveness != Lifesign.Uncertain, "Owner's liveness is already uncertain'");
        _;
    }

    modifier notDead() {
        require(liveness != Lifesign.Dead, "Owner is no longer alive");
        _;
    }

    modifier onlyDead() {
        require(liveness == Lifesign.Dead || liveness == Lifesign.PlayingDead, "Owner has not been confirmed as dead");
        _;
    }


    /// @notice Accept ETH deposits
    /// @dev To avoid exceeding gas limit don't perform any other actions
    receive() external payable { }

    // User management

    /// @notice Transfer ownership of this estate contract to another address
    /// @notice newOwner Address of account to transfer ownership to
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is missing");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Set the oracle that can report the owner's death. Set to zero-address to disable
    /// @param newOracle Address of oracle which is able to make trusted reports of the estate owner's death
    function changeOracle(address newOracle) public onlyOwner {
        // Allow setting to zero address to disable oracle
        // require(newOracle != address(0), "New oracle is missing");
        emit OracleChanged(oracle, newOracle);
        oracle = newOracle;
    }

    /// @notice Set the executor's address. Set to zero-address to disable
    /// @param newExecutor Address of the executor who will take over management of the estate after confirmation of death
    function changeExecutor(address newExecutor) public onlyOwnerOrExecutor {
        // Allow setting to zero address to remove executor
        // require(newExecutor != address(0), "New executor is missing");
        emit ExecutorChanged(executor, newExecutor);
        executor = newExecutor;
    }

    /// @notice Estate controller (owner or executor following confirmation of death) adds a beneficiary
    /// @param newBeneficiary Address of the beneficiary to be added
    /// @param shares Number of shares to be assigned to the new beneficiary and increasing the total number of shares assigned to all beneficiaries
    /// @dev Number of shares may be zero to permit recovery and report-of-death operations without granting rights to inheritance
    function addBeneficiary(address newBeneficiary, uint256 shares) public onlyController {
        require(newBeneficiary != address(0), "New beneficiary is missing");
        require(beneficiaryIndex[newBeneficiary] == 0, "New address is already a registered beneficiary");
        beneficiaries.push(newBeneficiary);
        uint256 index = beneficiaries.length;
        beneficiaryIndex[newBeneficiary] = index;
        beneficiaryShares[newBeneficiary] = shares;
        totalShares = SafeMath.add(totalShares, shares);
        emit AddedBeneficiary(newBeneficiary, shares);
    }

    /// @notice Estate controller (owner or executor following confirmation of death) removes a beneficiary
    /// @param beneficiary Address of the beneficiary to be removed. Any shares they have will be removed from the total.
    function removeBeneficiary(address beneficiary) public onlyController {
        require(beneficiary != address(0), "Beneficiary address is missing");
        uint256 index = beneficiaryIndex[beneficiary];
        require(index > 0, "Address is not a registered beneficiary");
        // Remove beneficiary
        for(uint256 i = index; i < beneficiaries.length; i++) {
            beneficiaries[i] = beneficiaries[i + 1];
        }
        beneficiaries.pop();
        beneficiaryIndex[beneficiary] = 0;
        // Remove beneficiary's shares
        uint256 sharesRemoved = beneficiaryShares[beneficiary];
        beneficiaryShares[beneficiary] = 0;
        totalShares = SafeMath.sub(totalShares, sharesRemoved);
        emit RemovedBeneficiary(beneficiary, sharesRemoved);
    }


    // Gnosis Safe configuration:

    /// @notice The Gnosis Safe associated with this contract acts as a co-owner and has the same permissions as the primary estate owner account
    /// @dev Set to zero address to disable Gnosis Safe co-ownership
    function setGnosisSafe(address newSafe) public onlyOwner {
        emit GnosisSafeChanged(gnosisSafe, newSafe);
        gnosisSafe = newSafe;
    }

    /// @notice Is a signature from the executor required to perform a recovery of the Gnosis Safe?
    function setIsExecutorRequiredForSafeRecovery(bool newValue) public onlyOwner {
        emit IsExecutorRequiredForSafeRecoveryChanged(newValue);
        isExecutorRequiredForSafeRecovery = newValue;
    }

    /// @notice Number of beneficiary signatures required to perform a recovery of the Gnosis Safe
    function setBeneficiariesRequiredForSafeRecovery(uint256 newValue) public onlyOwner {
        emit BeneficiariesRequiredForSafeRecoveryChanged(newValue);
        beneficiariesRequiredForSafeRecovery = newValue;
    }


    // Gnosis Safe recovery:

    /// @dev Allows an executor or beneficiary to confirm a Safe recovery transaction.
    /// @param dataHash Safe transaction hash.
    // TODO: Rename this function to make it's specific purpose more clear
    function confirmTransaction(bytes32 dataHash)
        public
        onlyMember
    {
        require(!isExecuted[dataHash], "Recovery already executed");
        isConfirmed[dataHash][msg.sender] = true;
    }

    /// @dev Returns if Safe transaction is a valid owner replacement transaction.
    /// @param prevOwner Owner that pointed to the owner to be replaced in the linked list
    /// @param oldOwner Owner address to be replaced.
    /// @param newOwner New owner address.
    function recoverAccess(address prevOwner, address oldOwner, address newOwner)
        public
        onlyMember
    {
        bytes memory data = abi.encodeWithSignature("swapOwner(address,address,address)", prevOwner, oldOwner, newOwner);
        bytes32 dataHash = getDataHash(data);
        require(!isExecuted[dataHash], "Recovery already executed");
        require(isConfirmedByRequiredParties(dataHash), "Recovery has not enough confirmations");
        isExecuted[dataHash] = true;
        // require(manager.execTransactionFromModule(address(manager), 0, data, Enum.Operation.Call), "Could not execute recovery");
        require(ModuleManager(gnosisSafe).execTransactionFromModule(gnosisSafe, 0, data, uint8(Operation.Call)), "Could not execute recovery");
    }

    /// @dev Returns if Safe transaction is a valid owner replacement transaction.
    /// @param dataHash Data hash.
    /// @return Confirmation status.
    // TODO: Rename this function to make it's specific purpose more clear
    function isConfirmedByRequiredParties(bytes32 dataHash)
        public
        view
        returns (bool)
    {
        if(isExecutorRequiredForSafeRecovery && !isConfirmed[dataHash][executor]) {
            return false;
        }
        if(beneficiariesRequiredForSafeRecovery > 0 && beneficiaries.length > 0) {
            uint256 confirmationCount;
            for (uint256 i = 0; i < beneficiaries.length; i++) {
                if (isConfirmed[dataHash][beneficiaries[i]]) {
                    confirmationCount++;
                }
                if (confirmationCount == beneficiariesRequiredForSafeRecovery) {
                    return true;
                }
            }

        }
        return false;
    }

    /// @dev Returns hash of data encoding owner replacement.
    /// @param data Data payload.
    /// @return Data hash.
    // TODO: Rename this function to make it's specific purpose more clear
    function getDataHash(bytes memory data)
        public
        pure
        returns (bytes32)
    {
        return keccak256(data);
    }


    // Dead Man's Switch:

    /// @notice The estate owner can enable or disable the dead man's switch
    /// @param newValue True to enable the dead man's switch, false to disable it
    function setIsDeadMansSwitchEnabled(bool newValue) public onlyOwner {
        emit IsDeadMansSwitchEnabledChanged(newValue);
        isDeadMansSwitchEnabled = newValue;
        if(true == newValue) {
            deadMansSwitchLastCheckin = block.timestamp;
        }
    }

    /// @notice The estate owner can set the time in seconds between check-ins before the dead man's switch can be triggered
    /// @param newValue Maximum safe time between check-ins in seconds
    function setDeadMansSwitchCheckinSeconds(uint256 newValue) public onlyOwner {
        require(0 != newValue, "Dead Man's Switch check-in seconds must be greater than zero");
        emit DeadMansSwitchCheckinSecondsChanged(newValue);
        deadMansSwitchCheckinSeconds = newValue;
    }


    // Asset management:

    /// @notice Send ETH from estate
    /// @param recipient Address to send ETH to
    /// @param amount How much ETH to send from the estate in Wei
    /// @return Success of transfer
    function sendEth(address payable recipient, uint256 amount) public onlyOwner returns(bool) {
        return recipient.send(amount);
    }

    /// @notice Send ERC20 token from estate
    /// @param recipient Address to send ERC20 token to
    /// @param token Address of ERC20 token to send
    /// @param amount How much of token to send from the estate in smallest unit
    /// @return Success of transfer
    function sendToken(address payable recipient, address token, uint256 amount) public onlyOwner returns(bool) {
        return IERC20(token).transfer(recipient, amount);
    }


    // Inheritance

    /// @notice Determine the number of tokens beneficiary is expected to receive based on their shares and the current estate balance
    /// @param beneficiary Address of the beneficiary to check
    /// @param token Address of the token to check or the zero-address for ETH
    function getBeneficiaryBalance(address beneficiary, address token) public view returns (uint256 shareBalance) {
        // Check if tokens have already been balanced
        if(isBeneficiaryTokenWithdrawn[beneficiary][token]) {
            return 0;
        }
        // Determine the total amount of ETH or tokens held if not yet known, but don't lock total in permanently
        uint totalTokens;
        if(totalTokensKnown[token] > 0) {
            totalTokens = totalTokensKnown[token];
        } else {
            if(address(0) == token) {
                totalTokens = address(this).balance;
            } else {
                totalTokens = IERC20(token).balanceOf(address(this));
            }
        }

        uint256 shareRatio = SafeMath.div(SafeMath.mul(precision, totalShares), beneficiaryShares[beneficiary]);
        uint256 share = SafeMath.div(SafeMath.mul(precision, totalTokens), shareRatio);

        return share;
    }


    // Life and death decisions:

    /// @notice  USE WITH CAUTION: while playing dead is temporary, actions taken by executors and beneficiaries during that time are permanent. Play dead to enable testing of post-death actions including executor control and beneficiary withdrawals.
    function playDead() public onlyOwner {
        emit PlayingDead();
        liveness = Lifesign.PlayingDead;
    }

    /// @notice Called by beneficiary or executor after owner has been reported dead and the waiting period has passed to establish confirmation of death
    function confirmDeath() public onlyMember {
        setDead();
    }

    /// @notice Called by beneficiary or executor to report death of the estate owner
    function reportDeath() public onlyMember {
        require(isDeadMansSwitchEnabled, "Dead Man's Switch is not enabled");
        require((deadMansSwitchLastCheckin + deadMansSwitchCheckinSeconds) < block.timestamp, "Dead Man's Switch timeout has not been reached");
        setUncertain();
    }

    /// @notice Called by estate owner to confirm they are still alive
    function confirmLife() public onlyOwner {
        setAlive();
    }

    /// @notice Set estate owner as alive and reset the dead man's switch timer if it's enabled
    function setAlive() internal notDead {
        emit ConfirmationOfLife(msg.sender);
        liveness = Lifesign.Alive;
        declareDeadAfter = 0;
        if(isDeadMansSwitchEnabled) {
            deadMansSwitchLastCheckin = block.timestamp;
        }
    }

    /// @notice Set estate owner's liveness as uncertain and establish time limit before death may be declared
    // Require notUncertain to prevent members from resetting the uncertaintyPeriod once already in an uncertain state
    function setUncertain() internal notDead notUncertain {
        emit ReportOfDeath(msg.sender);
        liveness = Lifesign.Uncertain;
        declareDeadAfter = block.timestamp + uncertaintyPeriod;
    }

    /// @notice If conditions permit, set the owner of the estate as dead
    function setDead() internal notDead {
        // Check if conditions have been met to declare death
        require(liveness == Lifesign.Uncertain, "Estate owners lifesigns are not currently in dispute");
        require(declareDeadAfter != 0, "No death confirmation timer has been set");
        require(declareDeadAfter < block.timestamp, "Not enough time has passed to confirm death");
        emit ConfirmationOfDeath();
        liveness = Lifesign.Dead;
    }
}
