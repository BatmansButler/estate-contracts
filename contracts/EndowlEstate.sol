// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

// endowl.com - Digital Inheritance Automation

//import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import "@openzeppelin/contracts/math/SafeMath.sol";

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

    /// @notice Has a distribution of the given token to the spcified beneficiary already occurred?
    mapping(address => mapping(address => bool)) public isBeneficiaryTokenWithdrawn;

    // TODO: Further evaluate if precision is sufficient for share ratios
    // precision is used for dividing up shares of assets...
    uint256 private precision = 8**10;

    // mapping(address => uint256) public totalTokensKnown;
    // address[] public trackedTokens;

    enum Lifesign { Alive, Uncertain, Dead, PlayingDead }

    /// @notice Estate owner's last known lifesign (0: Alive, 1: Uncertain, 2: Dead, 3: PlayingDead)
    Lifesign public liveness;

    /// @notice If not zero, the timestamp after which the estate owner may be declared dead
    uint256 public declareDeadAfter;
    /// @notice The amount of time after death is reported before it can be confirmed
    uint256 public uncertaintyPeriod = 8 weeks;

    // TODO: Ability to modify uncertaintyPeriod

    // Dead Man's Switch settings
    /// @notice Is the dead man's switch enabled
    bool public isDMSwitchEnabled;
    /// @notice How frequently (in seconds) must the estate owner check-in before the dead man's switch can be triggered
    uint256 public dMSwitchCheckinSeconds;
    /// @notice Timestamp of the estate owner's last check-in
    uint256 public dMSwitchLastCheckin;

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


    /// @notice Called by beneficiary or executor after owner has been reported dead and the waiting period has passed to establish confirmation of death
    function confirmDeath() public onlyMember {
        setDead();
    }

    /// @notice Called by beneficiary or executor to report death of the estate owner
    function reportDeath() public onlyMember {
        require(isDMSwitchEnabled, "Dead Man's Switch is not enabled");
        require((dMSwitchLastCheckin + dMSwitchCheckinSeconds) < block.timestamp, "Dead Man's Switch timeout has not been reached");
        setUncertain();
    }

    /// @notice Called by estate owner to confirm they are still alive
    function confirmLife() public onlyOwner {
        setAlive();
    }

    /// @notice Send ETH from estate
    /// @param recipient Address to send ETH to
    /// @param amount How much ETH to send from the estate in Wei
    /// @return Success of transfer
    function sendEth(address payable recipient, uint256 amount) public onlyOwner returns(bool) {
//        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not the estate owner");
        return recipient.send(amount);
    }

    /// @notice Send ERC20 token from estate
    /// @param recipient Address to send ERC20 token to
    /// @param token Address of ERC20 token to send
    /// @param amount How much of token to send from the estate in smallest unit
    /// @return Success of transfer
    function sendToken(address payable recipient, address token, uint256 amount) public onlyOwner returns(bool) {
//        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not the estate owner");
        return IERC20(token).transfer(recipient, amount);
    }

    /// @notice Set estate owner as alive and reset the dead man's switch timer if it's enabled
    function setAlive() internal notDead {
        emit ConfirmationOfLife(msg.sender);
        liveness = Lifesign.Alive;
        declareDeadAfter = 0;
        if(isDMSwitchEnabled) {
            dMSwitchLastCheckin = block.timestamp;
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
