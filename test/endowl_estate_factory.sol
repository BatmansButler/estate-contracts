// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/EndowlEstateFactory.sol";
import "../contracts/EndowlEstate.sol";

/// @title Endowl Estate Factory tests
/// @author endowl.com
contract TestEndowlEstateFactory {
    uint public initialBalance = 1 ether;
    uint256 lastSalt = 0;

    function unusedSalt() internal returns (uint256) {
        lastSalt = lastSalt + 1;
        return lastSalt;
    }

    /// @dev Test that passing different salts to getEstateAddress produces different results
    function testGetEstateAddressDifferentSalt() public {
        EndowlEstateFactory factory = EndowlEstateFactory(DeployedAddresses.EndowlEstateFactory());
        uint256 salt;
        address creator;
        address expected1;
        address expected2;

        // Compare expected addresses when the creator matches but the salt is different
        salt = 0;
        creator = address(this);
        expected1 = factory.getEstateAddress(creator, salt);
        salt = 1;
        creator = address(this);
        expected2 = factory.getEstateAddress(creator, salt);
        Assert.notEqual(expected1, expected2, "Addresses should be different when salt is different");
    }

    /// @dev Test that passing different creator addresses to getEstateAddress produces different results
    function testGetEstateAddressDifferentCreator() public {
        EndowlEstateFactory factory = EndowlEstateFactory(DeployedAddresses.EndowlEstateFactory());
        uint256 salt;
        address creator;
        address expected1;
        address expected2;

        // Compare expected addresses when the creator is different but the salt matches
        salt = 0;
        creator = 0x110001b0A438E46d4558bdE95b466b2852f3489f;
        expected1 = factory.getEstateAddress(creator, salt);
        salt = 0;
        creator = 0x11010e4A89486d9BCb66EE0d5EEFDed3ef8f68e9;
        expected2 = factory.getEstateAddress(creator, salt);
        Assert.notEqual(expected1, expected2, "Addresses should be different when creator is different");
    }

    function testNewEstateWithEmptyParams() public {
        EndowlEstateFactory factory = EndowlEstateFactory(DeployedAddresses.EndowlEstateFactory());
        // Create a new estate with default empty parameters
        uint256 salt = unusedSalt();
        address owner = address(0);
        address oracle = address(0);
        address executor = address(0);
        address payable estateAddress = factory.newEstate(salt, owner, oracle, executor);
        EndowlEstate estate = EndowlEstate(estateAddress);
        // Confirm this test contract owns the new estate
        Assert.equal(estate.owner(), address(this), "Estate should be owned by this address");
        // Confirm oracle and executor are not set (ie. zero address)
        Assert.equal(estate.oracle(), address(0), "Oracle should not be set");
        Assert.equal(estate.executor(), address(0), "Executor should not be set");
        // Compare expected and actual address of estate contract deployment
        address creator = address(this);
        address expected = factory.getEstateAddress(creator, salt);
        Assert.equal(expected, address(estate), "Estate address does not match expected address");
    }

    function testNewEstateWithFilledParams() public {
        EndowlEstateFactory factory = EndowlEstateFactory(DeployedAddresses.EndowlEstateFactory());

        // Create a new estate with parameters filled in
        uint256 salt = unusedSalt();
        address owner = 0x110001b0A438E46d4558bdE95b466b2852f3489f;
        address oracle = 0x66F16412E633d8B4630855f39C37690ACF685228;
        address executor = 0x11010e4A89486d9BCb66EE0d5EEFDed3ef8f68e9;
        address payable estateAddress = factory.newEstate(salt, owner, oracle, executor);
        EndowlEstate estate = EndowlEstate(estateAddress);
        // Confirm this test contract owns the new estate
        Assert.equal(estate.owner(), owner, "Estate should be owned by the designated address");
        Assert.equal(estate.oracle(), oracle, "Oracle should be the designated address");
        Assert.equal(estate.executor(), executor, "Executor should be the designated address");
        // Compare expected and actual address of estate contract deployment
        address creator = address(this);
        address expected = factory.getEstateAddress(creator, salt);
        Assert.equal(expected, address(estate), "Estate address does not match expected address");
    }

    /// @dev Test that the same creator calling newEstate with the same salt more than once fails
    function testMultipleCallsToNewEstatesWithSameSaltAndCreator() public {
        EndowlEstateFactory factory = EndowlEstateFactory(DeployedAddresses.EndowlEstateFactory());
        // Create a new estate with default empty parameters
        uint256 salt = unusedSalt();
        address owner = address(0);
        address oracle = address(0);
        address executor = address(0);
        // Call factory.newEstate twice with the same parameters
        bytes memory newEstateData = abi.encodeWithSelector(EndowlEstateFactory.newEstate.selector, salt, owner, oracle, executor);
        bool r;
        // First call with new salt should succeed
        (r, ) = address(factory).call(newEstateData);
        Assert.isTrue(r, "First call to newEstate should succeed");
        // Second call with same salt and same caller should fail (contract already exists)
        (r, ) = address(factory).call(newEstateData);
        Assert.isFalse(r, "Second call to newEstate from the same address and using the same salt should fail");
    }

}
