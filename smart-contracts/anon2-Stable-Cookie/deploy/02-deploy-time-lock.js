const verify = require("../helper-functions");
const { networkConfig, developmentChains, MIN_DELAY } = require("../helper-hardhat-config");

module.exports = async (hre) => {
  const { getNamedAccounts, deployments, network } = hre
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()
  log("_______________________________________________________________")
  log("\n🚀 Deploying TimeLock and waiting for confirmations... 🚀")

  log("******************************hardhat deploy logs******************************")
  const timeLockContract = await deploy("TimeLock", {
    from: deployer,
    args: [MIN_DELAY, [], [], deployer],
    log: false,
    waitConfirmations: networkConfig[network.name].blockConfirmations || 1,
  })
  log("*******************************************************************************")

  log(`🎉 TimeLock at ${timeLockContract.address} 🎉`)
  if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    await verify(timeLockContract.address, [])
  }
};

module.exports.tags = ["all", "timelock"];