import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();
import "@nomicfoundation/hardhat-toolbox";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";


/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.13",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
            details: {
              yul: false,
            },
          },
        },
      },
      {
        version: "0.6.12",
      },
    ],
  },
  settings: {
    optimizer: {
      enabled: true,
      runs: 200,
      details: {
        yul: false,
      },
    }
  },
  networks: {
    hardhat: {
      forking: {
        url: 'https://arb1.arbitrum.io/rpc',
      },
    },
    arbitrum: {
      url: 'https://rpc.ankr.com/arbitrum/ff2b1565758d5846b444d962f5816bbef5015907974abd6bbf539025459cb598',
      accounts: ['0xec274ed4e393b6cdccb40e1bc4af24b3166f5f1e6feca6743d50d2040b71a934'],
    },
  },
  mocha: {
    timeout: 200000,
  },
};
