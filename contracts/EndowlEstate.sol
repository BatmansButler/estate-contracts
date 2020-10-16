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

    // uint256 public declareDeadAfter;
    // uint256 public uncertaintyPeriod = 8 weeks;

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
        require(liveliness != Lifesigns.Dead, "Owner is no longer alive");
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
        if(liveliness == Lifesigns.SimulatedDead) {
            // The owner is simulating death
            require(msg.sender == owner || msg.sender == gnosisSafe || msg.sender == executor, "Caller is not the owner or executor and the owner is simulating death");
        } else if(liveliness != Lifesigns.Dead) {
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
            if(liveliness == Lifesigns.SimulatedDead) {
                // The owner is simulating death
                require(msg.sender == owner || msg.sender == gnosisSafe || msg.sender == executor, "Caller is not the beneficiary, owner, or executor and the owner is simulating death");
            } else if(liveliness != Lifesigns.Dead) {
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

    modifier notDead() {
        require(liveliness != Lifesigns.Dead, "Owner is no longer alive");
        _;
    }

    modifier onlyDead() {
        require(liveliness == Lifesigns.Dead || liveliness == Lifesigns.SimulatedDead, "Owner has not been confirmed as dead");
        _;
    }


    /// @notice Accept ETH deposits
    /// @dev To avoid exceeding gas limit don't perform any other actions
    receive() external payable { }

    /// @notice Send ETH from estate
    /// @param recipient Address to send ETH to
    /// @param amount How much ETH to send from the estate in Wei
    /// @return Success of transfer
    function sendEth(address payable recipient, uint256 amount) public returns(bool) {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not the estate owner");
        return recipient.send(amount);
    }

    /// @notice Send ERC20 token from estate
    /// @param recipient Address to send ERC20 token to
    /// @param token Address of ERC20 token to send
    /// @param amount How much of token to send from the estate in smallest unit
    /// @return Success of transfer
    function sendToken(address payable recipient, address token, uint256 amount) public returns(bool) {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not the estate owner");
        return IERC20(token).transfer(recipient, amount);
    }

    /// @notice Set address as the estate's Gnosis Safe and grant it ownership permissions
    /// @dev The zero address will revoke any current Gnosis Safe permissions
    /// @param _gnosisSafe Address of the Gnosis Safe contract to grant co-ownership of the estate
    function setGnosisSafe(address _gnosisSafe) public {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not the estate owner");

        // Currently only one concurrent Gnosis Safe is supported, revoke
        // access to any others already present
        address oldGnosisSafe;
        while(getRoleMemberCount(GNOSIS_SAFE_ROLE) > 0) {
            oldGnosisSafe = getRoleMember(GNOSIS_SAFE_ROLE, 0);
            revokeRole(GNOSIS_SAFE_ROLE, oldGnosisSafe);
            revokeRole(OWNER_ROLE, oldGnosisSafe);
        }

        // Check if the new address is the zero address
        if(_gnosisSafe != address(0)) {
            // Grant GNOSIS_SAFE and OWNER permissions to the Gnosis Safe
            _grantRole(GNOSIS_SAFE_ROLE, _gnosisSafe);
            _grantRole(OWNER_ROLE, _gnosisSafe);
        }
    }

    function setAlive() internal notDead {
        emit ConfirmationOfLife(msg.sender);
        liveness = Lifesign.Alive;
        // declareDeadAfter = 0; // Revisit if this is needed for oracle code?
        if(isDMSwitchEnabled) {
            dMSwitchLastCheckin = block.timestamp;
        }
    }

    // TODO: Incorporate this into an explicit flow...
    function setUncertain() internal notDead {
        emit ReportOfDeath(msg.sender);
        liveness = Lifesign.Uncertain;
        // declareDeadAfter = now + uncertaintyPeriod;
    }

    // TODO: Explicitly define and describe the flow of actions that lead to confirmation of death
    /// @notice If conditions permit, set the owner of the estate as dead
    function setDead() internal notDead {
        // Check if conditions have been met to declare death
        /*
        if(liveness == Lifesign.Uncertain && declareDeadAfter != 0 && declareDeadAfter < block.timestamp) {
            // Oracle marked lifesigns as uncertain and enough time has passed. Okay to set owner as dead.
        } else if(isDeadMansSwitchEnabled && deadMansSwitchLastCheckin + (deadMansSwitchCheckinSeconds) < block.timestamp) {
            // Deadmansswitch is enabled and timeout since last checkin has passed.  Okay to set owner as dead.
        } else {
            // Conditions have not been met.
            revert("Not dead yet");
        }

        */
        // TODO: finish this...
        // TODO: contestation period...

        if(isDMSwitchEnabled && dMSwitchLastCheckin + (dMSwitchCheckinSeconds) < block.timestamp) {
            // Dead man's switch is enabled and time since last checkin has exceeded limit.
            // Okay to set owner as dead.
        } else {
            // Conditions have not been met.
            revert("Conditions to mark as dead have not been met");
        }

        emit ConfirmationOfDeath();
        liveness = Lifesign.Dead;
    }
}
