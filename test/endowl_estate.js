const EndowlEstate = artifacts.require("EndowlEstate");

const OWNER_ROLE = web3.utils.keccak256("OWNER_ROLE");
const EXECUTOR_ROLE = web3.utils.keccak256("EXECUTOR_ROLE");
const BENEFICIARY_ROLE = web3.utils.keccak256("BENEFICIARY_ROLE");
const GNOSIS_SAFE_ROLE = web3.utils.keccak256("GNOSIS_SAFE_ROLE");

contract("EndowlEstate", async accounts => {
    it("should have 1 initial owner", async () => {
        let instance = await EndowlEstate.deployed();
        let ownerCount = await instance.getRoleMemberCount(OWNER_ROLE);
        assert.equal(ownerCount, 1);
    });

    it("should be owned by the first account", async () => {
        let instance = await EndowlEstate.deployed();
        let owner = await instance.getRoleMember(OWNER_ROLE, 0);
        assert.equal(owner, accounts[0]);
    })

    it("should have 0 initial executors", async () => {
        let instance = await EndowlEstate.deployed();
        let ownerCount = await instance.getRoleMemberCount(EXECUTOR_ROLE);
        assert.equal(ownerCount, 0);
    });

    it("should have an initial 'liveness' value of 0 (ie. 'Alive')", async () => {
        let instance = await EndowlEstate.deployed();
        let liveness = await instance.liveness()
        assert.equal(liveness, 0);
    });

    let sendAmount = web3.utils.toWei("10", "ether");

    it("should accept direct ETH payments", async () => {
        let instance = await EndowlEstate.deployed();
        let estateBalance = await web3.eth.getBalance(instance.address);
        assert.equal(estateBalance, 0);
        await instance.send(sendAmount);
        estateBalance = await web3.eth.getBalance(instance.address);
        assert.equal(estateBalance, sendAmount);
    });

    it("should send ETH on behalf of owner", async () => {
        let instance = await EndowlEstate.deployed();
        let estateBalance = await web3.eth.getBalance(instance.address);
        // Confirm the ETH payment from the previous test is present
        assert.equal(estateBalance, sendAmount);
        let user = accounts[0];
        // let userBalanceBefore = web3.utils.toBN(await web3.eth.getBalance(user));
        let userBalanceBefore = await web3.eth.getBalance(user);
        console.log("userBalanceBefore:", userBalanceBefore);
        await instance.sendEth(user, sendAmount);
        estateBalance = await web3.eth.getBalance(instance.address);
        assert.equal(estateBalance, 0);
        // let userBalanceAfter = web3.utils.toBN(await web3.eth.getBalance(user));
        let userBalanceAfter = await web3.eth.getBalance(user);
        console.log("userBalanceAfter:", userBalanceAfter);
        console.log("sendAmount:", sendAmount);
        let expectedUserBalance = web3.utils.toBN(sendAmount).add(web3.utils.toBN(userBalanceBefore));
        console.log("expectedUserBalance:", expectedUserBalance.toString());
        // assert.equal(userBalanceAfter, userBalanceBefore.plus(web3.utils.toWei("10", "ether")));
        // Confirm the first user's balance goes up by sendAmount
        console.log("...:", expectedUserBalance.eq(web3.utils.toBN(userBalanceAfter)));
        assert.equal(true, expectedUserBalance.eq(web3.utils.toBN(userBalanceAfter)));
    });
})
