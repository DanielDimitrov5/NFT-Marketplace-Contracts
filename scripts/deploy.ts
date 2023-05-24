import { ethers } from "hardhat";
import { NFT__factory, Marketplace__factory, NFT, Marketplace } from "../typechain-types";

async function main() {
    const nftFactory = (await ethers.getContractFactory("NFT")) as NFT__factory;
    const nft: NFT = await nftFactory.deploy("NFT", "NFT");

    const [deployer, addr1] = await ethers.getSigners();

    const marketplaceFactory = (await ethers.getContractFactory("Marketplace")) as Marketplace__factory;
    const marketplace: Marketplace = await marketplaceFactory.deploy(deployer.address, 3);

    await nft.deployed();
    await marketplace.deployed();

    console.log("NFT deployed to:", nft.address);
    console.log("Marketplace deployed to:", marketplace.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
