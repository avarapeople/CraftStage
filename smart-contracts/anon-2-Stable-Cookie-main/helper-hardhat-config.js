const networkConfig = {
    localhost: {},
    hardhat: {},
    sepolia: {
      blockConfirmations: 6,
    },
  };
  
  const developmentChains = ["hardhat", "localhost"];
  
  // Governor Variables
  const QUORUM_PERCENTAGE = 2; 
  const MIN_DELAY = 7200; 
  const VOTING_PERIOD = 3;
  const VOTING_DELAY = 1; 
  const ADDRESS_ZERO = "0x0000000000000000000000000000000000000000";
  
  // CookieStore Variables
  const WETH = "0xdd13E55209Fd76AfE204dBda4007C227904f0a81"
  const WBTC = "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063"
  const WETHUSDPRICEFEED = "0x694AA1769357215DE4FAC081bf1f309aDC325306" 
  const WBTCUSDPRICEFEED = "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43"

  const NEW_COLLATERAL_TOKEN = ["0x779877A7B0D9E8603169DdbD7836e478b4624789","0xc59E3633BAAC79493d908e63626716e204A45EdF"];
  const FUNC = "addTokenCollateral";
  const PROPOSAL_DESCRIPTION = "Add LINK token as collateral";
  
  module.exports = {
    networkConfig,
    developmentChains,
    QUORUM_PERCENTAGE,
    MIN_DELAY,
    VOTING_PERIOD,
    VOTING_DELAY,
    ADDRESS_ZERO,
    WETH,
    WBTC,
    WETHUSDPRICEFEED,
    WBTCUSDPRICEFEED,
    NEW_COLLATERAL_TOKEN,
    FUNC,
    PROPOSAL_DESCRIPTION,
  };
  