const verify = require("../helper-functions");
const { networkConfig,
  developmentChains,
  QUORUM_PERCENTAGE,
  VOTING_PERIOD,
  VOTING_DELAY,
} = require("../helper-hardhat-config");

module.exports = async (hre) => {
  const { getNamedAccounts, deployments, network } = hre
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()
  const governanceTokenContract = await get("GovernanceToken")
  const timeLockContract = await get("TimeLock")
  const args = [
    governanceTokenContract.address,
    timeLockContract.address,
    QUORUM_PERCENTAGE,
    VOTING_PERIOD,
    VOTING_DELAY,
  ]

  log("_______________________________________________________________")
  log("\n🚀 Deploying GovernorContract and waiting for confirmations... 🚀")

  log("******************************hardhat deploy logs******************************")
  const governorContract = await deploy("GovernorContract", {
    from: deployer,
    args,
    log: false,
    waitConfirmations: networkConfig[network.name].blockConfirmations || 1,
  })
  log(`🎉 GovernorContract at ${governorContract.address} 🎉`)
  if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    await verify(governorContract.address, args)
  }
};

module.exports.tags = ["all", "governor"];