import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { getPreviousBlockTimestamp, getBlockTimestamp } from "./helpers/getBlockTimestamp";
import { increaseTime as increaseTimeHelper } from "./helpers/increaseTime";

import { BigNumber, Contract, ContractFactory } from "ethers";
import { expect } from "chai";
import hre, { ethers, network } from "hardhat";

const { parseEther: toWei } = ethers.utils;
const { provider, getSigners, constants } = ethers;

const increaseTime = (time: number) => increaseTimeHelper(provider, time);

const toBN = (num: any) => BigNumber.from(num);
const toNano = (value: string) => ethers.utils.parseUnits(value, 6);
const oneYear = 31536000; // In seconds

let deployer: SignerWithAddress;
let user1: SignerWithAddress;
let whaleWETH: SignerWithAddress;

let ArbitrageExecutor: ContractFactory;
let AaveInvestment: ContractFactory;
let executor: Contract;
let investment: Contract;
let usdt: Contract;
let weth: Contract;
let uniswap: Contract;
let sushiswap: Contract;

const SUSHISWAP_ROUTER = "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F";
const UNISWAP_ROUTER = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
const POOL_PROVIDER = "0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e";
const USDT = "0xdAC17F958D2ee523a2206206994597C13D831ec7";
const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const WHALE_WETH = "0x8EB8a3b98659Cce290402893d0123abb75E3ab28"; // 65,252 ETH
// Sushiswap Token0: WETH, token1: USDT
// Uniswap Token0: WETH, token1: USDT

describe("ArbitrageExecutor", () => {
  beforeEach(async () => {
    await reset();

    [deployer, user1] = await getSigners();
    whaleWETH = await impersonateAccount(WHALE_WETH);
    uniswap = await ethers.getContractAt("IUniswapV2Router02", UNISWAP_ROUTER);
    sushiswap = await ethers.getContractAt("IUniswapV2Router02", SUSHISWAP_ROUTER);
    ArbitrageExecutor = await ethers.getContractFactory("ArbitrageExecutor");
    executor = await ArbitrageExecutor.deploy(POOL_PROVIDER, uniswap.address, sushiswap.address, WETH, USDT);
    usdt = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", USDT);
    weth = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/IERC20.sol:IERC20", WETH);

    // Creating an arbitrage opportunity on sushiswap
    // Here we provide a lot of WETH in exchange for USDT this makes
    // WETH cheaper compared to USDT. This simulates many people
    // buying a lot of USDT from this pool
    const wethAmountToSwap = toWei("3000");
    const deadline = (await getPreviousBlockTimestamp()).add(500);
    await weth.connect(whaleWETH).approve(sushiswap.address, wethAmountToSwap);
    await sushiswap
      .connect(whaleWETH)
      .swapExactTokensForTokens(wethAmountToSwap, 0, [WETH, USDT], whaleWETH.address, deadline);
  });

  describe("Should allow to interact with the Arbitrage Executor contract", () => {
    it("Should allow to execute a FlashLoan", async () => {
      const flashLoanAmount = toNano("1000000");
      const usdtUserBalanceBefore = await usdt.balanceOf(deployer.address);
      expect(usdtUserBalanceBefore).to.be.equal(0);

      const slippageTolerance = toWei("1"); // 1% tolerance
      const { minimumFirstSwap, minimumSecondSwap } = await executor.estimateSlippage(
        flashLoanAmount,
        slippageTolerance
      );
      await executor.executeFlashLoan(USDT, flashLoanAmount, minimumFirstSwap, minimumSecondSwap);
      const usdtUserBalanceAfter = await usdt.balanceOf(deployer.address);
      expect(usdtUserBalanceAfter).to.be.gte(0);
    });

    it("Should get the path of the from and to", async () => {
      const path = await executor.getPath(USDT, WETH);
      expect(path[0]).to.be.equal(USDT);
      expect(path[1]).to.be.equal(WETH);
    });

    it("Should fail to deploy the arbitrage executor using an invalid provider", async () => {
      let errorMsg;
      try {
        await ArbitrageExecutor.deploy(constants.AddressZero, uniswap.address, sushiswap.address, WETH, USDT);
        errorMsg = "No error occurred";
      } catch (error: any) {
        errorMsg = error.reason.toString();
      }
      expect(errorMsg.includes('InputIsZero("PROVIDER")')).to.be.equal(true);
    });

    it("Should fail to deploy the arbitrage executor using an invalid uniswap router", async () => {
      let errorMsg;
      try {
        await ArbitrageExecutor.deploy(POOL_PROVIDER, constants.AddressZero, sushiswap.address, WETH, USDT);
        errorMsg = "No error occurred";
      } catch (error: any) {
        errorMsg = error.reason.toString();
      }
      expect(errorMsg.includes('InputIsZero("UNISWAP_ROUTER")')).to.be.equal(true);
    });

    it("Should fail to deploy the arbitrage executor using an invalid sushiswap router", async () => {
      let errorMsg;
      try {
        await ArbitrageExecutor.deploy(POOL_PROVIDER, uniswap.address, constants.AddressZero, WETH, USDT);
        errorMsg = "No error occurred";
      } catch (error: any) {
        errorMsg = error.reason.toString();
      }
      expect(errorMsg.includes('InputIsZero("SUSHISWAP_ROUTER")')).to.be.equal(true);
    });

    it("Should fail to deploy the arbitrage executor using an invalid token0", async () => {
      let errorMsg;
      try {
        await ArbitrageExecutor.deploy(POOL_PROVIDER, uniswap.address, sushiswap.address, constants.AddressZero, USDT);
        errorMsg = "No error occurred";
      } catch (error: any) {
        errorMsg = error.reason.toString();
      }
      expect(errorMsg.includes('InputIsZero("TOKEN0")')).to.be.equal(true);
    });

    it("Should fail to deploy the arbitrage executor using an invalid token1", async () => {
      let errorMsg;
      try {
        await ArbitrageExecutor.deploy(POOL_PROVIDER, uniswap.address, sushiswap.address, WETH, constants.AddressZero);
        errorMsg = "No error occurred";
      } catch (error: any) {
        errorMsg = error.reason.toString();
      }
      expect(errorMsg.includes('InputIsZero("TOKEN1")')).to.be.equal(true);
    });

    it("Should fail to execute a flash loan with invalid owner", async () => {
      await expect(executor.connect(user1).executeFlashLoan(USDT, 0, 0, 0)).to.be.rejectedWith(
        "Ownable: caller is not the owner"
      );
    });

    it("Should fail to call the executeOperation directly", async () => {
      await expect(executor.executeOperation(USDT, 0, 0, constants.AddressZero, "0x00")).to.be.rejectedWith(
        "InvalidCaller"
      );
    });

    it("Should fail to estimate the slippage with invalid value", async () => {
      await expect(executor.estimateSlippage(1, toWei("101"))).to.be.rejectedWith("InvalidSlippage");
    });
  });

  describe("Should interact with the AaveInvestment contract", () => {
    beforeEach(async () => {
      AaveInvestment = await ethers.getContractFactory("AaveInvestment");
      investment = await AaveInvestment.deploy(POOL_PROVIDER, USDT);

      // Simulates a good arbitrage opportunity
      const flashLoanAmount = toNano("1000000");
      const slippageTolerance = toWei("1"); // 1% tolerance
      const { minimumFirstSwap, minimumSecondSwap } = await executor.estimateSlippage(
        flashLoanAmount,
        slippageTolerance
      );
      await executor.executeFlashLoan(USDT, flashLoanAmount, minimumFirstSwap, minimumSecondSwap);
    });

    it("Should fail to deploy the aave investment using an invalid provider", async () => {
      let errorMsg;
      try {
        await AaveInvestment.deploy(constants.AddressZero, USDT);
        errorMsg = "No error occurred";
      } catch (error: any) {
        errorMsg = error.reason.toString();
      }
      expect(errorMsg.includes('InputIsZero("PROVIDER")')).to.be.equal(true);
    });

    it("Should fail to deploy the aave investment using an invalid provider", async () => {
      let errorMsg;
      try {
        await AaveInvestment.deploy(POOL_PROVIDER, constants.AddressZero);
        errorMsg = "No error occurred";
      } catch (error: any) {
        errorMsg = error.reason.toString();
      }
      expect(errorMsg.includes('InputIsZero("TOKEN")')).to.be.equal(true);
    });

    it("Should allow to invest in Aave after a good arbitrage", async () => {
      const usdtUserBalance = await usdt.balanceOf(deployer.address);
      await usdt.approve(investment.address, usdtUserBalance);
      await investment.invest(usdtUserBalance);
      const aaveLp = await investment.getTotalAaveLpBalance();
      expect(aaveLp).to.be.equal(usdtUserBalance);
    });

    it("Should fail to invest in Aave with invalid user", async () => {
      const usdtUserBalance = await usdt.balanceOf(deployer.address);
      await usdt.approve(investment.address, usdtUserBalance);
      await expect(investment.connect(user1).invest(usdtUserBalance)).to.be.rejectedWith(
        "Ownable: caller is not the owner"
      );
    });

    it("Should fail to withdraw with invalid user", async () => {
      const usdtUserBalance = await usdt.balanceOf(deployer.address);
      await usdt.approve(investment.address, usdtUserBalance);
      await investment.invest(usdtUserBalance);
      await expect(investment.connect(user1).withdraw(1)).to.be.rejectedWith("Ownable: caller is not the owner");
    });

    it("Should fail to withdraw more than balance", async () => {
      const usdtUserBalance = await usdt.balanceOf(deployer.address);
      await usdt.approve(investment.address, usdtUserBalance);
      await investment.invest(usdtUserBalance);
      const aaveLp1 = await investment.getTotalAaveLpBalance();
      expect(aaveLp1).to.be.equal(usdtUserBalance);
      1;
      await expect(investment.withdraw(aaveLp1.add(10000))).to.be.rejectedWith("InsufficientBalanceToWithdraw");
    });

    it("Should allow to partially withdraw from Aave and get some profit", async () => {
      const usdtUserBalance = await usdt.balanceOf(deployer.address);
      await usdt.approve(investment.address, usdtUserBalance);
      await investment.invest(usdtUserBalance);
      const aaveLp1 = await investment.getTotalAaveLpBalance();
      expect(aaveLp1).to.be.equal(usdtUserBalance);
      1;
      // Increasing time for one year to earn some yield on the deposit
      await increaseTime(oneYear);

      await investment.withdraw(aaveLp1.div(2));
      const aaveLp2 = await investment.getTotalAaveLpBalance();
      await investment.withdraw(aaveLp2);
      const aaveLp3 = await investment.getTotalAaveLpBalance();
      expect(aaveLp3.div(1e6)).to.be.equal(0);

      const usdtUserBalanceAfter = await usdt.balanceOf(deployer.address);
      expect(usdtUserBalanceAfter).to.be.gte(usdtUserBalance);
    });

    it("Should allow to totally withdraw from Aave and get some profit", async () => {
      const usdtUserBalance = await usdt.balanceOf(deployer.address);
      await usdt.approve(investment.address, usdtUserBalance);
      await investment.invest(usdtUserBalance);
      const aaveLp1 = await investment.getTotalAaveLpBalance();
      expect(aaveLp1).to.be.equal(usdtUserBalance);
      1;
      // Increasing time for one year to earn some yield on the deposit
      await increaseTime(oneYear);

      await investment.withdraw(aaveLp1);
      const usdtUserBalanceAfter = await usdt.balanceOf(deployer.address);
      expect(usdtUserBalanceAfter).to.be.gte(usdtUserBalance);
    });
  });
});

async function reset() {
  await network.provider.request({
    method: "hardhat_reset",
    params: [
      {
        forking: {
          jsonRpcUrl: `${process.env.ETHEREUM_MAINNET_RPC}`,
          blockNumber: Number(process.env.MAINNET_FORK_BLOCK_NUMBER || 0),
        },
      },
    ],
  });
}

async function impersonateAccount(address: string) {
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [address],
  });

  return await ethers.getSigner(address);
}
