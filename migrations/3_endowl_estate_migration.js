var EndowlEstate = artifacts.require("EndowlEstate");

module.exports = function(deployer) {
    // deployment steps
    deployer.deploy(EndowlEstate);
}
