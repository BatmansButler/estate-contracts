// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/EndowlEstate.sol";

contract TestEndowlEstate1 {
    uint public initialBalance = 1 ether;

    receive() external payable {}

    function testInitialLiveness() public {
        EndowlEstate estate = EndowlEstate(DeployedAddresses.EndowlEstate());
        Assert.equal(uint(estate.liveness()), uint(0), "Initial liveness should be 0, ie. Alive");
        Assert.equal(uint(estate.liveness()), uint(EndowlEstate.Lifesign.Alive), "Initial liveness should be equal to EndowlEstate.Lifesign.Alive");
    }

    function testInitialDeadMansSwitchSettings() public {
        EndowlEstate estate = EndowlEstate(DeployedAddresses.EndowlEstate());
        Assert.isFalse(estate.isDeadMansSwitchEnabled(), "Dead Man's Switch should be off initially");
    }
}

/*
contract TestEndowlEstate2 {
    uint public initialBalance = 1 ether;

    function testNewEstateOwnedByCaller() public {
        EndowlEstate estate = new EndowlEstate();
        Assert.equal(estate.owner(), address(this), "Newly deployed estate should be owned by calling account");
    }

    function testSendingEthToEstate() public {
//        EndowlEstate estate = EndowlEstate(DeployedAddresses.EndowlEstate());
        EndowlEstate estate = new EndowlEstate();
        Assert.equal(address(estate).balance, 0, "Estate balance should initially be zero");
        Assert.equal(address(this).balance, initialBalance, "Testing contract balance should be preloaded to initialBalance");
        (bool success, ) = address(estate).call{value: initialBalance}("");
        Assert.isTrue(success, "Sending ETH to estate should succeed");
        Assert.equal(address(estate).balance, initialBalance, "Estate balance should become initialBalance");
    }

    function testSendEth() public {
        EndowlEstate estate = EndowlEstate(DeployedAddresses.EndowlEstate());
        Assert.equal(address(estate).balance, initialBalance, "Estate balance should be initialBalance at start of test");
        Assert.equal(address(this).balance, 0, "Testing contract balance should be zero at start of test");
        bytes memory callData = abi.encodeWithSelector(EndowlEstate.sendEth.selector, address(this), initialBalance);
        (bool success, ) = address(estate).call(callData);
        Assert.isTrue(success, "Calling sendEth from owning account should succeed");
        Assert.equal(address(this).balance, initialBalance, "Testing contract balance should be specified amount");
        Assert.equal(address(estate).balance, 0, "Estate balance should be zero");
    }
}
*/
