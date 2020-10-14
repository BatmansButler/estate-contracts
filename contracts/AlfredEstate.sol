// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

// Alfred.Estate - Digital Inheritance Automation

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//import "@openzeppelin/contracts/math/SafeMath.sol";

/// @title Digital Inheritance Automation
/// @author Alfred.Estate
contract AlfredEstate is AccessControl {
    // Define access control roles
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant BENEFICIARY_ROLE = keccak256("BENEFICIARY_ROLE");
    // bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant GNOSIS_SAFE_ROLE = keccak256("GNOSIS_SAFE_ROLE");

    enum Lifesign { Alive, Uncertain, Dead, PlayingDead }

    /// @notice Estate owner's last known lifesign (0: Alive, 1: Uncertain, 2: Dead, 3: PlayingDead)
    Lifesign public liveness;

    // Dead Man's Switch settings

    /// @notice Is the dead man's switch enabled
    bool public isDMSwitchEnabled;
    /// @notice How frequently (in seconds) must the estate owner check-in before the dead man's switch can be triggered
    uint256 public dMSwitchCheckinSeconds;
    /// @notice Timestamp of the estate owner's last check-in
    uint256 public dMSwitchLastCheckin;

    /// @notice The estate owner is simulating death, which is more temporary than actually being dead
    event PlayingDead();
    /// @notice The estate owner is considered to be dead
    event ConfirmationOfDeath();
    /// @notice A report of the estate owner's death has been received from a trusted source
    event ReportOfDeath(address indexed reporter);
    /// @notice The estate owner has been confirmed to be alive
    event ConfirmationOfLife(address indexed reporter);



    /// @notice Initialize new  estate to be owned by the caller
    constructor() {
        // Grant the contract deployer the default admin role: it will be able
        // to grant and revoke any roles
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        // Set the estate owner as alive
        liveness = Lifesign.Alive;
    }

    /// @notice Require the estate owner to be presumed still alive
    modifier notDead() {
        require(liveness != Lifesign.Dead, "Owner is no longer considered alive");
        _;
    }

    /// @notice Require the estate owner to be considered dead or playing dead
    modifier onlyDead() {
        require(liveness == Lifesign.Dead || liveness == Lifesign.PlayingDead, "Owner is presumed alive");
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
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        return recipient.send(amount);
    }

    /// @notice Send ERC20 token from estate
    /// @param recipient Address to send ERC20 token to
    /// @param token Address of ERC20 token to send
    /// @param amount How much of token to send from the estate in smallest unit
    /// @return Success of transfer
    function sendToken(address payable recipient, address token, uint256 amount) public returns(bool) {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Caller is not an admin");
        return IERC20(token).transfer(recipient, amount);
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
