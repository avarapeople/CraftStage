const verify = require("../helper-functions");
const { networkConfig, developmentChains } = require("../helper-hardhat-config");
const { ethers } = require("hardhat");

// Passing the Hardhat Runtime Environment as a parameter
module.exports = async (hre) => {
    const { getNamedAccounts, deployments, network } = hre
    const { deploy, log } = deployments
    const { deployer } = await getNamedAccounts()
    log("\n✨ ________________________________ DAO SETUP ________________________________ ✨")
    log("\n🚀 Deploying GovernanceToken and waiting for confirmations... 🚀")

    log("******************************hardhat deploy logs******************************")
    const governanceTokenContract = await deploy("GovernanceToken", {
        from: deployer,
        args: [],
        log: false,
            waitConfirmations: networkConfig[network.name].blockConfirmations || 1,
    })
    log("*******************************************************************************")

    log(`🎉 GovernanceToken at ${governanceTokenContract.address} 🎉`)
    // Verify the contract only on non-development chains with Etherscan API key
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        await verify(governanceTokenContract.address, [])
    }

    log(`📝 Delegating tokens to ${deployer}... 📝`)
    await delegate(governanceTokenContract.address, deployer)
    log("🎉 Tokens delegated! 🎉")
};

// Define a delegate function to perform contract delegation
const delegate = async (governanceTokenAddress, delegatedAccount) => {
    const governanceToken = await ethers.getContractAt("GovernanceToken", governanceTokenAddress)
    const transactionResponse = await governanceToken.delegate(delegatedAccount)
    await transactionResponse.wait(1)

    // Check that the checkpoint was updated
    console.log(`Checkpoints: ${await governanceToken.numCheckpoints(delegatedAccount)}`)
}


module.exports.tags = ["all", "governor"];