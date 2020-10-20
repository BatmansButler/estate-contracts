const EndowlEstate = artifacts.require("EndowlEstate");

const OWNER_ROLE = web3.utils.keccak256("OWNER_ROLE");
const EXECUTOR_ROLE = web3.utils.keccak256("EXECUTOR_ROLE");
const BENEFICIARY_ROLE = web3.utils.keccak256("BENEFICIARY_ROLE");
const GNOSIS_SAFE_ROLE = web3.utils.keccak256("GNOSIS_SAFE_ROLE");

contract("EndowlEstate", async accounts => {
    it("should be owned by the first account", async () => {
        let instance = await EndowlEstate.deployed();
        let owner = await instance.owner();
        assert.equal(owner, accounts[0]);
    })

    it("should have an initial 'liveness' value of 0 (ie. 'Alive')", async () => {
        let instance = await EndowlEstate.deployed();
        let liveness = await instance.liveness()
        assert.equal(liveness, 0);
    });

    // How much ETH to test sending to and from the estate
    let sendAmount = web3.utils.toWei("10", "ether");

    it("should accept direct ETH payments", async () => {
        let instance = await EndowlEstate.deployed();
        let estateBalance = await web3.eth.getBalance(instance.address);
        // Confirm the estate balance is initially zero ETH
        assert.equal(estateBalance, 0);
        // Send ETH directly to the estate
        await instance.send(sendAmount);
        // Confirm the estate balance increased by the amount sent
        estateBalance = await web3.eth.getBalance(instance.address);
        assert.equal(estateBalance, sendAmount);
    });

    it("should send ETH on behalf of owner", async () => {
        let instance = await EndowlEstate.deployed();
        let estateBalance = await web3.eth.getBalance(instance.address);
        // Confirm the ETH payment from the previous test is present
        assert.isTrue(web3.utils.toBN(estateBalance).gt(web3.utils.toBN(0)), "Estate balance is greater than zero");
        assert.equal(estateBalance, sendAmount, "Estate balance is expected amount");
        // Send ETH to a different recipient than the active user
        let recipient = accounts[1];
        let recipientBalanceBefore = await web3.eth.getBalance(recipient);
        await instance.sendEth(recipient, sendAmount);
        // Send the whole amount that the estate previously received
        estateBalance = await web3.eth.getBalance(instance.address);
        // Confirm the estate balance is zero ETH/
        assert.equal(estateBalance, 0, "Estate balance is zero ETH after sending");
        let recipientBalanceAfter = await web3.eth.getBalance(recipient);
        let expectedRecipientBalance = web3.utils.toBN(sendAmount).add(web3.utils.toBN(recipientBalanceBefore));
        // Confirm the recipient's balance goes up by sendAmount
        assert.isTrue(expectedRecipientBalance.eq(web3.utils.toBN(recipientBalanceAfter)), "Recipients final balance increased as expected");
    });

    // TODO: Test sendToken
})
