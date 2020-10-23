const EndowlEstate = artifacts.require("EndowlEstate");
let catchRevert = require("./utils/exceptions").catchRevert;

contract("EndowlEstate", async accounts => {
    let estate;
    let owner = accounts[0];
    let nonOwner = accounts[1];
    // How much ETH to test sending to and from the estate
    let sendAmount = web3.utils.toBN(web3.utils.toWei("10", "ether"));

    before(async () => {
        // estate = await EndowlEstate.deployed();
        estate = await EndowlEstate.new();
    })

    it("should be owned by the first account", async () => {
        assert.equal(owner, await estate.owner());
    })

    it("should have an initial 'liveness' value of 0 (ie. 'Alive')", async () => {
        assert.equal(await estate.liveness(), 0);
    });

    it("should accept direct ETH payments from the owner", async () => {
        let estateBalanceBefore = web3.utils.toBN(await web3.eth.getBalance(estate.address));
        await estate.send(sendAmount);
        let estateBalanceAfter = web3.utils.toBN(await web3.eth.getBalance(estate.address));
        let expectedEstateBalance = estateBalanceBefore.add(sendAmount);
        assert.isTrue(expectedEstateBalance.eq(estateBalanceAfter));
    });

    it("should accept direct ETH payments from a non-owner", async () => {
        let estateBalanceBefore = web3.utils.toBN(await web3.eth.getBalance(estate.address));
        await estate.send(sendAmount, {from: nonOwner});
        let estateBalanceAfter = web3.utils.toBN(await web3.eth.getBalance(estate.address));
        let expectedEstateBalance = estateBalanceBefore.add(sendAmount);
        assert.isTrue(expectedEstateBalance.eq(estateBalanceAfter));
    });

    it("should send ETH when the owner calls sendEth(...)", async () => {
        // Some balance of ETH should still be on the estate from previous test and is needed for this test
        let estateBalanceBefore = web3.utils.toBN(await web3.eth.getBalance(estate.address));
        assert.isTrue(estateBalanceBefore.gte(sendAmount), "Test requires estate balance be at least sendAmount");

        // Set recipient to a different account than the caller so we don't have to calculate for gas fees
        let recipient = nonOwner;
        let recipientBalanceBefore = web3.utils.toBN(await web3.eth.getBalance(recipient));

        // Call sendEth from the owner
        await estate.sendEth(recipient, sendAmount);

        // Confirm the estate balance goes down by the expected amount
        let estateBalanceAfter = web3.utils.toBN(await web3.eth.getBalance(estate.address));
        let expectedEstateBalance = estateBalanceBefore.sub(sendAmount);
        assert.isTrue(expectedEstateBalance.eq(estateBalanceAfter), "Wrong estate balance after sendEth()");

        // Confirm the recipient's balance goes up by the expected amount
        let recipientBalanceAfter = web3.utils.toBN(await web3.eth.getBalance(recipient));
        let expectedRecipientBalance = recipientBalanceBefore.add(sendAmount);
        assert.isTrue(expectedRecipientBalance.eq(recipientBalanceAfter), "Wrong recipient balance after sendEth()");
    });

    it("should revert the transaction when non-owners call sendEth(...)", async () => {
        // Some balance of ETH should still be on the estate from previous test and is needed for this test
        let estateBalanceBefore = web3.utils.toBN(await web3.eth.getBalance(estate.address));
        assert.isTrue(estateBalanceBefore.gte(sendAmount), "Test requires estate balance be at least sendAmount");
        // Call sendEth from a non-owner, which should fail with a revert
        await catchRevert(estate.sendEth(owner, sendAmount, {from: nonOwner}));
    })

    it("should start playing dead when the owner calls playDead()", async () => {
        assert.equal(await estate.liveness(), 0, "Test requires estate owner to be alive");
        await estate.playDead();
        assert.equal(await estate.liveness(), 3, "Playing dead should produce liveness value of 3");
    })

    it("should stop playing dead when the owner calls confirmLife()", async () => {
        assert.equal(await estate.liveness(), 3, "Test requires estate owner to be playing dead (liveness value of 3");
        await estate.confirmLife();
        assert.equal(await estate.liveness(), 0, "Confirming life should produce liveness value of 0");
    })

    it("should revert the transaction when a non-owner calls playDead()", async () => {
        await catchRevert(estate.playDead({from: nonOwner}));
    })

    // TODO: Test roles that can successfully call reportDeath() and under what conditions
    // TODO: Test roles that can successfully call confirmDeath() and under what conditions
    // TODO: Test that calling confirmLife() after confirmation of death fails
    // TODO: Test oracleCallback...
    // TODO: Test uncertainty period after report of death and before confirmation of death
    // TODO: Test executor control after confirmation of death...
    // TODO: Test beneficiaries claiming shares...
    // TODO: Test executors distributing shares...
    // TODO: Test sendToken...
})
