const verify = require("../helper-functions");
const { ADDRESS_ZERO } = require("../helper-hardhat-config");

module.exports = async (hre) => {
    const { getNamedAccounts, deployments  } = hre
  const { log } = deployments
  const { deployer } = await getNamedAccounts()
   
  const timeLock = await ethers.getContract("TimeLock", deployer)
  const governor = await ethers.getContract("GovernorContract", deployer)

  log("_______________________________________________________________")
  log("\n✏️ Setting up contracts for roles... ✏️")
  log("...")
  // Get roles
  const proposerRole = await timeLock.PROPOSER_ROLE()
  const executorRole = await timeLock.EXECUTOR_ROLE()
  const adminRole = await timeLock.TIMELOCK_ADMIN_ROLE()

  // Grant roles
  const proposerTx = await timeLock.grantRole(proposerRole, governor.target)
  await proposerTx.wait(1)
  const executorTx = await timeLock.grantRole(executorRole, ADDRESS_ZERO)
  await executorTx.wait(1)
    // Revoke role
const revokeTx = await timeLock.revokeRole(adminRole, deployer)
  await revokeTx.wait(1)

  log("✨ THE DAO IS READY! ✨")

};

module.exports.tags = ["all", "setup"];