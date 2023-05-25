import { NFT__factory, Marketplace__factory, NFT, Marketplace } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { keccak256, toUtf8Bytes } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";


describe("NFT Marketplace", () => {

    let nft: NFT;
    let marketplace: Marketplace;

    let deployer: SignerWithAddress;
    let addr1: SignerWithAddress;

    const URI = "ipfs://QmQ9Z";
    const price = ethers.utils.parseEther("1");

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
                await expect(listItemTx).to.emit(marketplace, "LogItemListed").withArgs(1, nft.address, 1, deployer.address, price);
            });

            it("Should revert if item is already listed", async () => {
                await expect(marketplace.listItem(1, price)).to.be.revertedWithCustomError(marketplace, "Marketplace__ItemAlreadyListed").withArgs(id);
            });
        });
    });

    describe("buyItem", () => {

        let total: BigNumber;

        before(async () => {
            const mint = await nft.mint(URI);
            await mint.wait();

            await marketplace.addItem(nft.address, 2);

            total = await marketplace.getTotalPrice(1);
        });

        it("Should revert if item with this Id does not exist", async () => {
            await expect(marketplace.buyItem(3)).to.be.revertedWithCustomError(marketplace, "Marketplace__ItemWithThisIdDoesNotExist").withArgs(3);
        });

        it("Should revert if item is not listed", async () => {
            await expect(marketplace.buyItem(2)).to.be.revertedWithCustomError(marketplace, "Marketplace__ThisItemIsNotListedForSale").withArgs(2);
        });

        it("Should revert if sent value is not enough", async () => {
            await expect(marketplace.buyItem(1, { value: total.sub(1) })).to.be.revertedWithCustomError(marketplace, "Marketplace__NotEnoughtFunds");
        });

        describe("token transfer", () => {

            let nftBalanceBefore: BigNumber;
            let nftBalanceAfter: BigNumber;

            let selletBalanceBefore: BigNumber;

            let fee: BigNumber;

            let buyTx: any;

            before(async () => {
                const approve = await nft.connect(deployer).approve(marketplace.address, 1);
                await approve.wait();

                nftBalanceBefore = await nft.balanceOf(addr1.address);
                selletBalanceBefore = await deployer.getBalance();

                buyTx = await marketplace.connect(addr1).buyItem(1, { value: total });
                await buyTx.wait();

                nftBalanceAfter = await nft.balanceOf(addr1.address);

                fee = total.sub(price);
            });

            it("Should transfer token to buyer", async () => {
                expect(await nft.ownerOf(1)).to.equal(addr1.address);
                expect((await marketplace.items(1)).owner).to.equal(addr1.address);
            });

            it("Should pay fee to contract", async () => {
                // console.log(await ethers.provider.getBalance(marketplace.address));
                expect(await ethers.provider.getBalance(marketplace.address)).to.equal(fee);
            });

            it("Should pay to the seller", async () => {
                const selletBalanceAfter = await deployer.getBalance();
                expect(selletBalanceAfter).to.equal(selletBalanceBefore.add(price));
            });

            it("Should return change to buyer", async () => {
                const approve = await nft.approve(marketplace.address, 2);
                await approve.wait();

                const list = await marketplace.listItem(2, price);
                await list.wait();

                const buyerBalanceBefore = await addr1.getBalance();

                const buy = await marketplace.connect(addr1).buyItem(2, { value: total.mul(2) });
                await buy.wait();

                const buyerBalanceAfter = await addr1.getBalance();

                expect(buyerBalanceAfter).to.be.closeTo(buyerBalanceBefore.sub(total), 109000000000000);
            });

            it("Should emit event", async () => {
                await expect(buyTx).to.emit(marketplace, "LogItemSold").withArgs(1, nft.address, 1, deployer.address, addr1.address, price);
            });
        });

    });

    describe("heleper functions", () => {

        describe("getTotalPrice", () => {

            before(async () => {
                const mint = await nft.mint(URI);
                await mint.wait();

                await marketplace.addItem(nft.address, 3);
            });

            it("Should revert if item with this Id does not exist", async () => {
                await expect(marketplace.getTotalPrice(4)).to.be.revertedWithCustomError(marketplace, "Marketplace__ItemWithThisIdDoesNotExist").withArgs(4);
            });

            it("Should revert if item is not listed", async () => {
                await expect(marketplace.getTotalPrice(3)).to.be.revertedWithCustomError(marketplace, "Marketplace__ThisItemIsNotListedForSale").withArgs(3);
            });

            it("Should return total price", async () => {

                const list = await marketplace.listItem(3, price);
                list.wait();

                const totalPrice = await marketplace.getTotalPrice(3);

                const expectedPrice = price.mul(100 + feePercent).div(100);

                expect(totalPrice).to.equal(expectedPrice);
            });
        });


        describe("getHash", () => {

            // it("Should return expected hash", async () => {
            //     const hash = await marketplace.getHash(nft.address, 1);

            //     const expectedHash = keccak256(toUtf8Bytes(nft.address + "1"));

            //     expect(hash).to.equal(expectedHash);
            // });
        });

    });
});