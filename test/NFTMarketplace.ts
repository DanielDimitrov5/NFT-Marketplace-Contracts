import { NFT__factory, Marketplace__factory, NFT, Marketplace } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { keccak256, toUtf8Bytes } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { expect } from "chai";


describe("NFT Marketplace", () => {

    let nft: NFT;
    let marketplace: Marketplace;

    let deployer: SignerWithAddress;
    let addr1: SignerWithAddress;

    const feePercent = 3;

    before(async () => {
        const nftFactory = (await ethers.getContractFactory("NFT")) as NFT__factory;
        nft = await nftFactory.deploy("NFT", "NFT Symbol");
        await nft.deployed();

        [deployer, addr1] = await ethers.getSigners();

        const marketplaceFactory = (await ethers.getContractFactory("Marketplace")) as Marketplace__factory;
        marketplace = await marketplaceFactory.deploy(deployer.address, feePercent);
        await marketplace.deployed();

    });

    describe("Deployment", () => {
        it("Should set feeAccount and feePercent", async () => {
            expect(await marketplace.feeAccount()).to.equal(deployer.address);
            expect(await marketplace.feePercent()).to.equal(feePercent);
        });
    });

    describe("addItem & listItem", () => {

        const URI = "ipfs://QmQ9Z";
        const price = ethers.utils.parseEther("1");

        let addItemtx: any;

        before(async () => {
            const tx = await nft.mint(URI);
            await tx.wait();

            addItemtx = await marketplace.connect(deployer).addItem(nft.address, 1);
            addItemtx.wait();
        });

        describe("addItem", () => {

            it("Should revert not owner of the token", async () => {
                await expect(marketplace.connect(addr1).addItem(nft.address, 1)).to.be.revertedWithCustomError(marketplace, "Marketplace__YouAreNotTheOwnerOfThisToken");
            });


            it("Should add item", async () => {
                expect(await marketplace.itemCount()).to.equal(1);

                const items = await marketplace.items(1);

                expect(items).to.deep.equal([1, nft.address, 1, deployer.address]);
            });

            it("Should emit event", async () => {
                await expect(addItemtx).to.emit(marketplace, "LogItemAdded").withArgs(1, nft.address, 1, deployer.address);
            });
        });

        describe("listItem", () => {

            let listItemTx: any;
            let id: string;

            before(async () => {
                listItemTx = await marketplace.listItem(1, price);
                listItemTx.wait();

                id = await marketplace.getHash(nft.address, 1);
            });

            it("Should revert if item is not added", async () => {
                await expect(marketplace.listItem(2, price)).to.be.revertedWithCustomError(marketplace, "Marketplace__ItemWithThisIdDoesNotExist");
            });

            it("Should revert not owner of the token", async () => {
                await expect(marketplace.connect(addr1).listItem(1, price)).to.be.revertedWithCustomError(marketplace, "Marketplace__YouAreNotTheOwnerOfThisToken");
            });

            it("Should list item", async () => {
                const item = await marketplace.listedItems(id);

                expect(item).to.deep.equal([id, nft.address, 1, deployer.address, price]);
            });

            it("Should emit event", async () => {
                await expect(listItemTx).to.emit(marketplace, "LogItemListed").withArgs(id, nft.address, 1, deployer.address, price);
            });

            it("Should revert if item is already listed", async () => {
                await expect(marketplace.listItem(1, price)).to.be.revertedWithCustomError(marketplace, "Marketplace__ItemAlreadyListed").withArgs(id);
            });
        });
    });
});