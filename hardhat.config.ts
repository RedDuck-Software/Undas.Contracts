import * as dotenv from "dotenv";
import "@tenderly/hardhat-tenderly"
import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import '@openzeppelin/hardhat-upgrades';
import "@nomiclabs/hardhat-etherscan";



dotenv.config();

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 1000,
      },
    },
  },
  networks: {
    ropsten: {
      url: process.env.ROPSTEN_URL || "",
      accounts:
        process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    goerli: {
      url: "https://eth-goerli.alchemyapi.io/v2/J8woMfRg2pXG2YeaBGECv8ipKZQ355yp",
      accounts: ['76c7ed9f19562992ffcce10d1ac5e153cf6649fef21749565727b22dc8822167'],
    },
    hardhat: {
      forking: {
        url: "https://eth-goerli.alchemyapi.io/v2/J8woMfRg2pXG2YeaBGECv8ipKZQ355yp",
      },
    },
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
  },
  etherscan: {
    apiKey: 'W22PSMDAMFFG229SH9JP5EEFM1E2DVZNK4',
  }
};

export default config;