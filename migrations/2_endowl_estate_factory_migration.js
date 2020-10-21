var EndowlEstateFactory = artifacts.require("EndowlEstateFactory");

module.exports = function(deployer) {
    // deployment steps
    deployer.deploy(EndowlEstateFactory);
}
