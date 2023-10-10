const verify = require("../helper-functions");
const {
  networkConfig,
  developmentChains,
  WETH,
  WBTC,
  WETHUSDPRICEFEED,
  WBTCUSDPRICEFEED
} = require("../helper-hardhat-config");

module.exports = async (hre) => {
  const { getNamedAccounts, deployments, network } = hre
  const { deploy, log, get } = deployments
  const { deployer } = await getNamedAccounts()
  const stableCookie = await get("StableCookie")
  const governor = await ethers.getContract("GovernorContract", deployer)

  log("----------------------------------------------------")
  log("Deploying CookieStore and waiting for confirmations...")
  const args = [[WETH, WBTC],
  [WETHUSDPRICEFEED, WBTCUSDPRICEFEED],
  stableCookie.address]
  log("_______________________________________________________________")
  log("\n🚀 Deploying CookieStore and waiting for confirmations... 🚀")
  // return
  log("******************************hardhat deploy logs******************************")
  const cookieStore = await deploy("CookieStore", {
    from: deployer,
    args,
    log: true,
    waitConfirmations: networkConfig[network.name].blockConfirmations || 1,
  })
  log("*******************************************************************************")

  log(`🎉 CookieStore at ${cookieStore.address} 🎉`)

  if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    await verify(cookieStore.address, [])
  }
  log("_______________________________________________________________")
  log("\n✏️ Setting up contracts for roles... ✏️")
  log("...")
  // Get role
  const addCollateralRole = await cookieStore.ADD_TOKEN_COLLATERAL_ROLE()

  // Grant role
  const addCollateralRoleTx = await cookieStore.grantRole(addCollateralRole, governor.address)
  await addCollateralRoleTx.wait(1)

  // Revoke role
  const revokeTx = await cookieStore.revokeRole(addCollateralRole, deployer)
  await revokeTx.wait(1)

  log("✨ COOKIES ARE READY! ✨")

};

module.exports.tags = ["all", "CookieStore"];