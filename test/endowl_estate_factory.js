const EndowlEstateFactory = artifacts.require("EndowlEstateFactory");
const EndowlEstate = artifacts.require("EndowlEstate");

const constants = {
    ZERO_ADDRESS : '0x0000000000000000000000000000000000000000'
};

contract("EndowlEstateFactory", async accounts => {

    let lastSalt = 0;
    function unusedSalt() {
        lastSalt++;
        return lastSalt;
    }

    it("getEstateAddress should produce a valid address", async () => {
        let instance = await EndowlEstateFactory.deployed();
        let salt = unusedSalt();
        let creator = accounts[0];
        let expected = await instance.getEstateAddress(creator, salt);
        assert.isTrue(web3.utils.isAddress(expected), "Result should be a valid address");
    })

    // TODO: Test that address returned by getEstateAddress matches a specific expected address

    it("getEstateAddress should produce different addresses for different salts", async () => {
        let instance = await EndowlEstateFactory.deployed();
        // Compare expected addresses when the creator matches but the salt is different
        // let salt = 0;
        let salt = unusedSalt();
        let creator = accounts[0];
        let expected1 = await instance.getEstateAddress(creator, salt);
        // console.log(expected1);
        salt = unusedSalt();
        let expected2 = await instance.getEstateAddress(creator, salt);
        assert.notEqual(expected1, expected2, "Addresses should be different when salt is different");
    })

    it("getEstateAddress should produce different addresses for different creators", async () => {
        let instance = await EndowlEstateFactory.deployed();
        // Compare expected addresses when the creator changes but the salt is the same
        assert.notEqual(accounts[0], accounts[1], "First two accounts should be different for testing");
        let salt = 0;
        let creator = accounts[0];
        let expected1 = await instance.getEstateAddress(creator, salt);
        creator = accounts[1];
        let expected2 = await instance.getEstateAddress(creator, salt);
        assert.notEqual(expected1, expected2, "Addresses should be different when creator is different");
    })

    it("newEstate should create an estate when called with an unused salt and zero-address for the other parameters", async() => {
        let instance = await EndowlEstateFactory.deployed();
        let salt = unusedSalt();
        let caller = accounts[0];
        let owner = constants.ZERO_ADDRESS;
        let oracle = constants.ZERO_ADDRESS;
        let executor = constants.ZERO_ADDRESS;
        let result = await instance.newEstate(salt, owner, oracle, executor);
        // Confirm TX succeeded
        assert.isTrue(result.receipt.status, "Transaction should succeed");
    })

    it("newEstate should generate an event with the estate and owners addresses", async() => {
        let instance = await EndowlEstateFactory.deployed();
        let salt = unusedSalt();
        let caller = accounts[0];
        let owner = constants.ZERO_ADDRESS;
        let oracle = constants.ZERO_ADDRESS;
        let executor = constants.ZERO_ADDRESS;
        let result = await instance.newEstate(salt, owner, oracle, executor);
        // Confirm TX succeeded
        assert.isTrue(result.receipt.status, "Transaction should succeed");
        // Check estate address from TX logs is set
        let estateAddress = result.logs[0].args.estate;
        assert.notEqual(estateAddress, constants.ZERO_ADDRESS, "A log entry should be emitted with the estate address");
        // Check address from TX logs matches expected address
        let expectedAddress = await instance.getEstateAddress(caller, salt);
        assert.equal(estateAddress, expectedAddress, "New estate address should match address produced by getEstateAddress");
        // Check owner address from TX logs is set and matches expectations
        let ownerAddress = result.logs[0].args.owner;
        assert.isTrue(web3.utils.isAddress(ownerAddress), "A let entry should be emitted identifying the owner");
    })

    it("newEstate should create an account owned by the caller when owner param is zero-address", async() => {
        let instance = await EndowlEstateFactory.deployed();
        let salt = unusedSalt();
        let caller = accounts[0];
        let owner = constants.ZERO_ADDRESS;
        let oracle = constants.ZERO_ADDRESS;
        let executor = constants.ZERO_ADDRESS;
        let result = await instance.newEstate(salt, owner, oracle, executor);
        // Confirm TX succeeded
        assert.isTrue(result.receipt.status, "Transaction should succeed");
        // Check estate address from TX logs is set
        let estateAddress = result.logs[0].args.estate;
        // Check that new estate is owned by the calling account according to the log
        let ownerAddress = result.logs[0].args.owner;
        assert.equal(ownerAddress, caller, "New estate owner in event log should be the calling account when owner param is zero-address");
        // Check that the new estate is owned by the calling account according to the estate contract
        let estate = await EndowlEstate.at(estateAddress);
        assert.equal(await estate.owner(), caller, "Estate should be owned by calling account when owner param is zero-address");


        // Check that oracle is not set
        assert.equal(await estate.oracle(), constants.ZERO_ADDRESS, "Oracle should not be set");
    })


    // TODO: Break testing apart for setting owner, oracle, and executor...

    // TODO: Add Javascript test where different creators use the same salt and the resulting estates
    //       should each be successfully created at different addresses

})
