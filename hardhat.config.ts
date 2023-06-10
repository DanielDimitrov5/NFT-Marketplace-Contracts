import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import { config as dotEnvConfig } from "dotenv";
dotEnvConfig();

const config: HardhatUserConfig = {
    solidity: "0.8.18",
    networks: {
        sepolia: {
            url: process.env.RPCURL_SEPOLIA,
            chainId: 11155111,
            accounts: [process.env.PRIVATE_KEY as string]
        }
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY
    }


};

export default config;
