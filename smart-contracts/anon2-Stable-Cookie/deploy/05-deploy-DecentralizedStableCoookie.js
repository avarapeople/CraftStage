const verify = require("../helper-functions");
const { networkConfig, developmentChains, MIN_DELAY } = require("../helper-hardhat-config");

module.exports = async (hre) => {
    const { getNamedAccounts, deployments, network } = hre
  const { deploy, log } = deployments
  const { deployer } = await getNamedAccounts()

  log("_______________________________________________________________")
  log("\n🚀 Deploying StableCookie and waiting for confirmations... 🚀")

  log("******************************hardhat deploy logs******************************")
  const stableCookie = await deploy("StableCookie", {
    from: deployer,
    args: [],
    log: false,
    waitConfirmations: networkConfig[network.name].blockConfirmations || 1,
  })
  log(`StableCookie at ${stableCookie.address}`)
  
  if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    await verify(stableCookie.address, [])
  }
};

module.exports.tags = ["all", "stableCookie"];