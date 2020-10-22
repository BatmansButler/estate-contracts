// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

// endowl.com - Digital Inheritance Automation

import "./EndowlEstate.sol";

/// @title Endowl Estate Factory
/// @author endowl.com
contract EndowlEstateFactory {
    /// @notice A new estate has been created
    event estateCreated(address indexed estate, address indexed owner);

    /// @notice Create a new estate owned by the caller
    /// @param salt Arbitrary number used while calculating address that estate will be deployed to; start with zero for first estate and increment for subsequent estates to get predictable addresses
    /// @param owner Optional address to assign ownership of the estate to
    /// @param oracle Optional trusted address to accept reports of death from
    /// @param executor Optional trusted address to assign as estate executor
    /// @return estateAddress Address that estate was deployed to
    /// @dev Use CREATE2 to create estate at pre-determinable address
    function newEstate(uint256 salt, address owner, address oracle, address executor) public payable returns (address payable estateAddress) {
        // TODO: Assess if the finalSalt should be based on the initial OWNER rather than the CALLER (in the event someone sets up an estate on behalf of someone else...)
        // Make the final salt uniquely specific to the caller
        bytes32 finalSalt = keccak256(abi.encodePacked(salt, msg.sender));
        // Deploy estate contract using CREATE2
        EndowlEstate estate = new EndowlEstate{salt: finalSalt}();
        // Initialize trusted parties if provided
        if(address(0) != oracle) {
            estate.changeOracle(oracle);
        }
        if(address(0) != executor) {
            estate.changeExecutor(executor);
        }
        // Set default owner to the caller if not specified
        if(address(0) == owner) {
            owner = msg.sender;
        }
        // Transfer ownership
        estate.transferOwnership(owner);
        emit estateCreated(address(estate), owner);
        return address(estate);
    }

    /// @notice Determine address that estate will be deployed to when using newEstate
    /// @param creator Address of the account calling newEstate
    /// @param salt Arbitrary number used while calculating address that estate gets deployed to
    /// @return estateAddress Address that estate will be deployed to
    function getEstateAddress(address creator, uint256 salt) public view returns (address estateAddress) {
        bytes32 finalSalt = keccak256(abi.encodePacked(salt, creator));
         estateAddress = address(uint(keccak256(abi.encodePacked(
            byte(0xff),
            address(this),
            finalSalt,
            keccak256(abi.encodePacked(
                type(EndowlEstate).creationCode
            ))
        ))));
    }

}
