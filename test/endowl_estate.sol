// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "truffle/Assert.sol";
import "truffle/DeployedAddresses.sol";
import "../contracts/EndowlEstate.sol";

contract TestEndowlEstate {
    uint public initialBalance = 1 ether;

    function testInitialLiveness() public {
        EndowlEstate estate = EndowlEstate(DeployedAddresses.EndowlEstate());
        Assert.equal(uint(estate.liveness()), uint(0), "Initial liveness should be 0, ie. Alive");
        Assert.equal(uint(estate.liveness()), uint(EndowlEstate.Lifesign.Alive), "Initial liveness should be equal to EndowlEstate.Lifesign.Alive");
    }

    function testInitialDeadMansSwitchSettings() public {
        EndowlEstate estate = EndowlEstate(DeployedAddresses.EndowlEstate());
        Assert.isFalse(estate.isDeadMansSwitchEnabled(), "Dead Man's Switch should be off initially");
    }

    function testSendingEthToEstate() public {
        EndowlEstate estate = EndowlEstate(DeployedAddresses.EndowlEstate());
        (bool success, ) = address(estate).call{value: initialBalance}("");
        Assert.isTrue(success, "Sending ETH to estate should succeed");
        Assert.equal(address(estate).balance, initialBalance, "Estate balance should be equal to initialBalance");
    }
}
