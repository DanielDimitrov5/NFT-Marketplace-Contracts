import { NFT__factory, NFT } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { expect } from "chai";

describe("NFT", () => {

    let nft: NFT;

    let deployer: SignerWithAddress;
    let addr1: SignerWithAddress;

    before(async () => {
        const nftFactory = (await ethers.getContractFactory("NFT")) as NFT__factory;
        nft = await nftFactory.deploy("NFT", "NFT Symbol");
        await nft.deployed();

        [deployer, addr1] = await ethers.getSigners();
    });

    describe("Deployment", () => {
        it("Should set name and symbol", async () => {
            expect(await nft.name()).to.equal("NFT");
            expect(await nft.symbol()).to.equal("NFT Symbol");
        });
    });

    describe("Minting", () => {

        const URI = "ipfs://QmQ9Z";

        it("Should mint a token", async () => {
            const mint = await nft.mint(URI);
            await mint.wait();

            expect(await nft.ownerOf(1)).to.equal(deployer.address);

            expect(await nft.tokenCount()).to.equal(1);
        });

        it("Should set token URI", async () => {
            expect(await nft.tokenURI(1)).to.equal(URI);
        });

        it("Should emit event", async () => {
            const mint = await nft.mint(URI);
            await mint.wait();

            await expect(mint).to.emit(nft, "LogNftMinted").withArgs(2, deployer.address, URI);
        });

        it("Should not mint if not owner", async () => {
            await expect(nft.connect(addr1).mint(URI)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
});