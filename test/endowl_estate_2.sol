// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "truffle/Assert.sol";
//import "truffle/DeployedAddresses.sol";
import "../contracts/EndowlEstate.sol";

contract TestEndowlEstate2 {
    uint public initialBalance = 1 ether;
    address payable estateAddress;

    /// @dev Necessary to receive payments back to this test contract
    receive() external payable {}

    /// @dev Verify owner of newly deployed estate is the caller
    function testNewEstateOwnedByCaller() public {
        EndowlEstate estate = new EndowlEstate();
        estateAddress = address(estate);
        Assert.equal(estate.owner(), address(this), "Newly deployed estate should be owned by calling account");
    }

    /// @dev Sending ETH directly to estate contract from test contract should succeed
    function testSendingEthToEstate() public {
        // Check ETH is on the test contract and not on the estate to begin the test
        Assert.equal(estateAddress.balance, 0, "Unexpected estate balance");
        Assert.equal(address(this).balance, initialBalance, "Unexpected testing balance");
        // Send ETH to the estate
        (bool success, ) = estateAddress.call{value: initialBalance}("");
        // Verify success
        Assert.isTrue(success, "Sending ETH to estate failed");
        Assert.equal(estateAddress.balance, initialBalance, "Unexpected estate balance after send");
    }

    /// @dev The owner of the estate should be able to call sendEth
    function testSendEth() public {
        // Check ETH is on the estate and not the test contract (from the previous test)
        Assert.equal(estateAddress.balance, initialBalance, "Unexpected estate balance");
        Assert.equal(address(this).balance, 0, "Unexpected testing balance");
        // Call and check success of estate.sendEth(address(this), initialBalance)
        bytes memory callData = abi.encodeWithSelector(EndowlEstate.sendEth.selector, address(this), initialBalance);
        (bool success, ) = estateAddress.call(callData);
        Assert.isTrue(success, "Calling sendEth from owner should succeed");
        // Check ETH value was transferred from estate to this testing contract
        Assert.equal(address(this).balance, initialBalance, "Unexpected testing balance");
        Assert.equal(estateAddress.balance, 0, "Unexpected estate balance");
    }
}
