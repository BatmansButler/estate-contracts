// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

// endowl.com - Digital Inheritance Automation

// NOTE: Compiled code size may exceed deployment limit as written due to strings contained in revert calls.
//       To reduce code size (at the cost of extra debugging info) set the compile option "debug.revertStrings" to "strip" in truffle-config.js.

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
// Interface generated from @gnosis.pm/safe-contracts/contracts/base/ModuleManager.sol
import "./IModuleManager.sol";
import "./IKyberNetworkProxy.sol";

/// @title Digital Inheritance Automation
/// @author endowl.com
contract EndowlEstate  {
    uint constant MAX_UINT = 2**256 - 1;

    // TODO: Assess if Kyber code is resilient to Kyber performing updates to their contracts
    address constant KYBER_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public KYBER_NETWORK_PROXY_ADDRESS = 0x818E6FECD516Ecc3849DAf6845e3EC868087B755;
    address constant REFERAL_ADDRESS = 0xdac3794d1644D7cE73d098C19f33E7e10271b2bC;

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
    /// @notice The amount of time after death is reported before it can be confirmed, stored in seconds
    uint256 public uncertaintyPeriod = 8 weeks;

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

    /// @notice Ownership of the estate as been transferred to a new address
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
    /// @notice Uncertainty Period timer has been modified to new number of seconds
    event UncertaintyPeriodChanged(uint256 indexed newValue);

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

    /// @dev If called by the owner, check them in as alive
    modifier ownerCheckin() {
        _;
//        if(isDeadMansSwitchEnabled && (msg.sender == owner || msg.sender == gnosisSafe)) {
        if(isDeadMansSwitchEnabled && isOwner(msg.sender)) {
            deadMansSwitchLastCheckin = block.timestamp;
        }
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender));
        // require(msg.sender == owner || msg.sender == gnosisSafe, "Not owner");
        // require(liveness != Lifesign.Dead, "Dead");
        _;
    }

    modifier onlyExecutor() {
        require(isExecutor(msg.sender), "Not executor");
        _;
    }

    modifier onlyOwnerOrExecutor() {
        require(isOwner(msg.sender) || isExecutor(msg.sender), "Not owner or executor");
        _;
    }

    modifier onlyController() {
        require(isController(msg.sender), "Not controller");
        _;
    }

    modifier onlyControllerOrBeneficiary(address beneficiary) {
        require(isController(msg.sender) || isBeneficiary(msg.sender), "Not controller or beneficiary");
        _;
    }

    modifier onlyBeneficiary() {
        require(isBeneficiary(msg.sender), "Beneficiary not found");
        _;
    }

    modifier onlyMember() {
        require(isOwner(msg.sender) || isExecutor(msg.sender) || isBeneficiary(msg.sender), "Member not found");
        _;
    }

    modifier onlyOracle() {
        require(isOracle(msg.sender), "Not oracle");
        _;
    }

    modifier notUncertain() {
        require(liveness != Lifesign.Uncertain, "Liveness uncertain");
        _;
    }

    modifier notDead() {
        require(liveness != Lifesign.Dead, "Dead");
        _;
    }

    modifier onlyDead() {
        require(liveness == Lifesign.Dead || liveness == Lifesign.PlayingDead, "Not dead");
        _;
    }


    /// @notice Accept ETH deposits
    /// @dev To avoid exceeding gas limit don't perform any other actions
    receive() external payable { }


    // User management

    /// @notice Transfer ownership of this estate contract to another address
    /// @notice newOwner Address of account to transfer ownership to
    function transferOwnership(address newOwner) public onlyOwner ownerCheckin {
        require(newOwner != address(0), "Address missing");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Set the oracle that can report the owner's death. Set to zero-address to disable
    /// @param newOracle Address of oracle which is able to make trusted reports of the estate owner's death
    function changeOracle(address newOracle) public onlyOwner ownerCheckin {
        // Allow setting to zero address to disable oracle
        emit OracleChanged(oracle, newOracle);
        oracle = newOracle;
    }

    /// @notice Set the executor's address. Set to zero-address to disable
    /// @param newExecutor Address of the executor who will take over management of the estate after confirmation of death
    function changeExecutor(address newExecutor) public onlyOwnerOrExecutor ownerCheckin {
        // Allow setting to zero address to remove executor
        emit ExecutorChanged(executor, newExecutor);
        executor = newExecutor;
    }

    /// @notice Estate controller (owner or executor following confirmation of death) adds a beneficiary
    /// @param newBeneficiary Address of the beneficiary to be added
    /// @param shares Number of shares to be assigned to the new beneficiary and increasing the total number of shares assigned to all beneficiaries
    /// @dev Number of shares may be zero to permit recovery and report-of-death operations without granting rights to inheritance
    function addBeneficiary(address newBeneficiary, uint256 shares) public onlyController ownerCheckin {
        require(newBeneficiary != address(0), "Address missing");
//        require(beneficiaryIndex[newBeneficiary] == 0, "Beneficiary exists");
        require(!isBeneficiary(newBeneficiary), "Beneficiary exists");
        beneficiaries.push(newBeneficiary);
        uint256 index = beneficiaries.length;
        beneficiaryIndex[newBeneficiary] = index;
        beneficiaryShares[newBeneficiary] = shares;
        totalShares = SafeMath.add(totalShares, shares);
        emit AddedBeneficiary(newBeneficiary, shares);
    }

    /// @notice Estate controller (owner or executor following confirmation of death) removes a beneficiary
    /// @param beneficiary Address of the beneficiary to be removed. Any shares they have will be removed from the total.
    function removeBeneficiary(address beneficiary) public onlyController ownerCheckin {
        require(beneficiary != address(0), "Address missing");
        uint256 index = beneficiaryIndex[beneficiary];
        require(index > 0, "Beneficiary not found");
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

    /// @notice Estate controller or beneficiary in question can change the address of a beneficiary
    /// @param oldAddress The current address of the beneficiary, to be replaced
    /// @param newAddress The new address to assign to the beneficiary, replacing the old address
    function changeBeneficiaryAddress(address oldAddress, address newAddress) public onlyControllerOrBeneficiary(oldAddress) ownerCheckin {
        require(oldAddress != address(0), "Address missing");
        require(newAddress != address(0), "New address missing");
//        require(beneficiaryIndex[oldAddress] > 0, "Beneficiary not found");
        require(isBeneficiary(oldAddress), "Beneficiary not found");
        uint256 index = beneficiaryIndex[oldAddress] - 1;
        uint256 shares = beneficiaryShares[oldAddress];
        beneficiaries[index] = newAddress;
        beneficiaryShares[oldAddress] = 0;
        beneficiaryShares[newAddress] = shares;
        emit ChangedBeneficiaryAddress(oldAddress, newAddress);
    }

    /// @notice Estate controller can change the number of shares assigned to the given beneficiary
    /// @param beneficiary Address controlled by beneficiary
    /// @param newShares Total number of shares to assign to the beneficiary
    function changeBeneficiaryShares(address beneficiary, uint256 newShares) public onlyController ownerCheckin {
        require(beneficiary != address(0), "Address missing");
//        require(beneficiaryIndex[beneficiary] > 0, "Beneficiary not found");
        require(isBeneficiary(beneficiary), "Beneficiary not found");
        uint256 oldShares = beneficiaryShares[beneficiary];
        totalShares = SafeMath.add(SafeMath.sub(totalShares, oldShares), newShares);
        beneficiaryShares[beneficiary] = newShares;
        emit ChangedBeneficiaryShares(beneficiary, oldShares, newShares);
    }

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


    // Gnosis Safe configuration:

    /// @notice The Gnosis Safe associated with this contract acts as a co-owner and has the same permissions as the primary estate owner account
    /// @dev Set to zero address to disable Gnosis Safe co-ownership
    function setGnosisSafe(address newSafe) public onlyOwner ownerCheckin {
        emit GnosisSafeChanged(gnosisSafe, newSafe);
        gnosisSafe = newSafe;
    }

    /// @notice Is a signature from the executor required to perform a recovery of the Gnosis Safe?
    function setIsExecutorRequiredForSafeRecovery(bool newValue) public onlyOwner ownerCheckin {
        emit IsExecutorRequiredForSafeRecoveryChanged(newValue);
        isExecutorRequiredForSafeRecovery = newValue;
    }

    /// @notice Number of beneficiary signatures required to perform a recovery of the Gnosis Safe
    function setBeneficiariesRequiredForSafeRecovery(uint256 newValue) public onlyOwner ownerCheckin {
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
        require(!isExecuted[dataHash], "Already executed");
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
        require(!isExecuted[dataHash], "Already executed");
        require(isConfirmedByRequiredParties(dataHash), "Not enough confirmations");
        isExecuted[dataHash] = true;
        // require(manager.execTransactionFromModule(address(manager), 0, data, Enum.Operation.Call), "Could not execute recovery");
        require(ModuleManager(gnosisSafe).execTransactionFromModule(gnosisSafe, 0, data, uint8(Operation.Call)), "Recovery failed");
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
    function setDeadMansSwitchCheckinSeconds(uint256 newValue) public onlyOwner ownerCheckin {
        require(0 != newValue, "Not zero");
        emit DeadMansSwitchCheckinSecondsChanged(newValue);
        deadMansSwitchCheckinSeconds = newValue;
    }

    /// @notice The estate owner can set the time in seconds between accepting a report of their death and confirming it
    /// @param newValue Minimum time in seconds that must pass following a valid report of death before a confirmation of death will be accepted
    function setUncertaintyPeriodSeconds(uint256 newValue) public onlyOwner ownerCheckin {
        require(0 != newValue, "Not zero");
        emit UncertaintyPeriodChanged(newValue);
        uncertaintyPeriod = newValue;
    }


    // Oracle

    /// @notice If an oracle is enable it may call this to report that the estate owner is believed to be dead
    /// @param isDead Is the oracle is reporting death?
    function oracleCallback(bool isDead) public onlyOracle notDead {
        if(isDead) {
            // Begin the uncertainty waiting period
            setUncertain();
        }
        else {
            // Reset the estate owner's status to alive
            // TODO: Explore if there are any cases where this could disrupt the owner's intended flow regarding the dead man's switch
            setAlive();
        }
    }


    // Asset management:

    /// @notice Send ETH from estate
    /// @param recipient Address to send ETH to
    /// @param amount How much ETH to send from the estate in Wei
    function sendEth(address payable recipient, uint256 amount) public onlyOwner ownerCheckin {
//        return recipient.send(amount);
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /// @notice Send ERC20 token from estate
    /// @param recipient Address to send ERC20 token to
    /// @param token Address of ERC20 token to send
    /// @param amount How much of token to send from the estate in smallest unit
    /// @return Success of transfer
    function sendToken(address payable recipient, address token, uint256 amount) public onlyOwner ownerCheckin returns(bool) {
        return IERC20(token).transfer(recipient, amount);
    }


    // Inheritance

    /// @notice After death has been confirmed, beneficiaries call this to receive their portion of the estate's ETH holdings
    function claimEthShares() public {
        claimTokenShares(address(0));
    }

    /// @notice After death has been confirmed, beneficiaries call this to receive their portion of the estate's holdings of the given ERC20 token
    /// @param token Address of ERC20 token to claim or zero-address from ETH
    function claimTokenShares(address token) public onlyDead onlyBeneficiary {
        determinePoolSize(token);
        sendShare(msg.sender, token, token);
    }

    /// @notice After death has been confirmed, beneficiaries call this to receive ETH in exchange for their portion of the estate's holdings of the given ERC20 token
    /// @param token Address of ERC20 token to exchange for ETH and claim
    function claimTokenSharesAsEth(address token) public onlyDead onlyBeneficiary {
        determinePoolSize(token);
        sendShare(msg.sender, token, address(0));
    }

    /// @notice After death has been confirmed, the executor can call this to cause the estate's holdings of ETH to be distributed to all beneficiaries
    function distributeEthShares() public {
        distributeTokenShares(address(0));
    }

    /// @notice After death has been confirmed, the executor can call this to cause the estate's holdings of the given token to be distributed to all beneficiaries
    /// @param token Address of ERC20 token to distribute or zero-address for ETH
    function distributeTokenShares(address token) public onlyDead onlyExecutor {
        determinePoolSize(token);
        for(uint256 i=0; i < beneficiaries.length; i++) {
            address payable b = address(uint160(beneficiaries[i]));
            sendShare(b, token, token);
        }
    }

    /// @notice After death has been confirmed, the executor can call this to cause the estate's holdings of the given token to be exchanged for ETH then distributed to all beneficiaries
    /// @param token Address of ERC20 token to exchange for ETH and distribute
    function distributeTokenSharesAsEth(address token) public onlyDead onlyExecutor {
        determinePoolSize(token);
        for(uint256 i=0; i < beneficiaries.length; i++) {
            address payable b = address(uint160(beneficiaries[i]));
            sendShare(b, token, address(0));
        }
    }

    /// @notice If not yet established, determine the total amount of ETH or ERC20 tokens held by the estate
    /// @dev This does not account for situations where the estate balance changes after being determined
    /// @param token Address of ERC20 or zero-address for ETH
    // TODO: Investigate risk and options regarding estate balance changing after pool size is determined, eg. after first beneficiary has withdrawn
    // TODO: Track expected balance and compare with actual balance, handle any detected discrepancies...
    function determinePoolSize(address token) internal {
        if(totalTokensKnown[token] == 0) {
            if(address(0) == token) {
                totalTokensKnown[token] = address(this).balance;
            } else {
                totalTokensKnown[token] = IERC20(token).balanceOf(address(this));
            }
        }
    }

    /// @notice Send share of ERC20 token or ETH to beneficiary, optionally exchanging token for ETH or a different ERC token first
    /// @param beneficiary Address of beneficiary to receive payment from the estate
    /// @param token Address of ERC20 token held by estate or zero-address for ETH
    /// @param receiveToken Address of ERC20 token to receive or zero-address for ETH. If not the same as origin 'token', an exchange will be attempted on Kyber
    function sendShare(address payable beneficiary, address token, address receiveToken) internal {
        if(!isBeneficiaryTokenWithdrawn[beneficiary][token]) {
            // TODO: Extensive testing of these operations for edge cases and rounding issues:
            uint256 shareRatio = SafeMath.div(SafeMath.mul(precision, totalShares), beneficiaryShares[beneficiary]);
            uint256 share = SafeMath.div(SafeMath.mul(precision, totalTokensKnown[token]), shareRatio);
            isBeneficiaryTokenWithdrawn[beneficiary][token] = true;
            if(address(0) == token) {
                require(beneficiary.send(share), "Send failed");
            } else {
                if(receiveToken != token) {
                    if(address(0) == receiveToken) {
                        receiveToken = KYBER_ETH_ADDRESS;
                    }
                    // Convert to desired token or ETH through Kyber
                    IERC20(token).approve(KYBER_NETWORK_PROXY_ADDRESS, 0);
                    IERC20(token).approve(KYBER_NETWORK_PROXY_ADDRESS, MAX_UINT);
                    uint256 min_conversion_rate;
                    uint256 result;
                    (min_conversion_rate,) = KyberNetworkProxy(KYBER_NETWORK_PROXY_ADDRESS).getExpectedRate(token, receiveToken, share);
                    result = KyberNetworkProxy(KYBER_NETWORK_PROXY_ADDRESS).tradeWithHint(token, share, receiveToken, beneficiary, MAX_UINT, min_conversion_rate, REFERAL_ADDRESS, '');
                    require(result > 0, "Kyber trade failed");
                } else {
                    // Don't require token transfer to succeed, since some tokens don't follow spec.
                    // TODO: Could use OpenZepelin SafeERC20 to guarantee transfer succeeded
                    IERC20(token).transfer(beneficiary, share);
                }
            }
            emit BeneficiaryWithdrawal(beneficiary, token, share);
        }
    }


    // Life and death decisions:

    /// @notice  USE WITH CAUTION: while playing dead is temporary, actions taken by executors and beneficiaries during that time are permanent. Play dead to enable testing of post-death actions including executor control and beneficiary withdrawals.
    function playDead() public onlyOwner ownerCheckin {
        emit PlayingDead();
        liveness = Lifesign.PlayingDead;
    }

    /// @notice Called by beneficiary or executor after owner has been reported dead and the waiting period has passed to establish confirmation of death
    function confirmDeath() public onlyMember {
        setDead();
    }

    /// @notice Called by beneficiary or executor to report death of the estate owner
    function reportDeath() public onlyMember {
        require(isDeadMansSwitchEnabled, "No Dead Man's Switch");
        require((deadMansSwitchLastCheckin + deadMansSwitchCheckinSeconds) < block.timestamp, "Timer not exceeded");
        setUncertain();
    }

    /// @notice Called by estate owner to confirm they are still alive
    function confirmLife() public onlyOwner ownerCheckin {
        setAlive();
    }

    /// @notice Is the given address a living owner
    /// @param who Address to check
    /// @return the address is an owner and considered alive
    function isOwner(address who) public view returns(bool) {
        if(liveness != Lifesign.Dead && (who == owner || who == gnosisSafe)) {
                return true;
        }
        return false;
    }

    function isExecutor(address who) public view returns(bool) {
        if(who == executor) {
            return true;
        }
        return false;
    }

    function isController(address who) public view returns(bool) {
        if(isOwner(who)) {
            return true;
        } else if(isExecutor(who) && (liveness == Lifesign.Dead || liveness == Lifesign.PlayingDead)) {
            return true;
        }
        return false;
    }


    function isBeneficiary(address who) public view returns(bool) {
        if(beneficiaryIndex[who] > 0) {
            return true;
        }
        return false;
    }


    function isOracle(address who) public view returns(bool) {
        if(who == oracle) {
            return true;
        }
        return false;
    }


    /// @notice Set estate owner as alive and reset the dead man's switch timer if it's enabled
    function setAlive() internal notDead {
        emit ConfirmationOfLife(msg.sender);
        liveness = Lifesign.Alive;
        declareDeadAfter = 0;
    // owner checkin moved to separate modifier function
    /*
        if(isDeadMansSwitchEnabled) {
            deadMansSwitchLastCheckin = block.timestamp;
        }
    */
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
        // Estate owners lifesigns are not currently in dispute
        require(liveness == Lifesign.Uncertain, "Liveness not uncertain");
        require(declareDeadAfter != 0, "Timer not started");
        require(declareDeadAfter < block.timestamp, "Timer not exceeded");
        emit ConfirmationOfDeath();
        liveness = Lifesign.Dead;
    }
}
