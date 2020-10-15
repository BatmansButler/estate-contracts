var AlfredEstate = artifacts.require("AlfredEstate");

module.exports = function(deployer) {
    // deployment steps
    deployer.deploy(AlfredEstate);
}
