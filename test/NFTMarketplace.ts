import { NFT__factory, Marketplace__factory, NFT, Marketplace } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { solidityKeccak256 } from "ethers/lib/utils";
import { ContractTransaction } from "@ethersproject/contracts";
import { ethers } from "hardhat";
import { expect } from "chai";
import { BigNumber } from "ethers";


describe("NFT Marketplace", () => {

    let nft: NFT;
    let marketplace: Marketplace;

    let deployer: SignerWithAddress;
    let addr1: SignerWithAddress;
    let addr2: SignerWithAddress;

    const URI = "ipfs://QmQ9Z";
    const price = ethers.utils.parseEther("1");

    const feePercent = 3;

    before(async () => {
        const nftFactory = (await ethers.getContractFactory("NFT")) as NFT__factory;
        nft = await nftFactory.deploy("NFT", "NFT Symbol");
        await nft.deployed();

        [deployer, addr1, addr2] = await ethers.getSigners();

        const marketplaceFactory = (await ethers.getContractFactory("Marketplace")) as Marketplace__factory;
        marketplace = await marketplaceFactory.deploy(feePercent);
        await marketplace.deployed();

    });

    describe("Deployment", () => {
        it("Should set feeAccount and feePercent", async () => {
            expect(await marketplace.feePercent()).to.equal(feePercent);
        });
    });

    describe("addCollection", () => {
        let addCollectionTx: ContractTransaction;

        before(async () => {
            addCollectionTx = await marketplace.addCollection(nft.address);
            await addCollectionTx.wait();
        });

        it("Should revert if collection is already added", async () => {
            await expect(marketplace.addCollection(nft.address)).to.be.revertedWithCustomError(marketplace, "Marketplace__CollectionAlreadyAdded").withArgs(nft.address);
        });

        it("Should add collection", async () => {
            expect(await marketplace.collectionCount()).to.equal(1);
            expect(await marketplace.collections(1)).to.equal(nft.address);
        });

        it("Should emit event", async () => {
            await expect(addCollectionTx).to.emit(marketplace, "LogCollectionAdded").withArgs(1, nft.address);
        });
    });

    describe("addItem & listItem", () => {
        let addItemtx: ContractTransaction;

        before(async () => {
            const nft1 = await nft.mint(URI);
            await nft1.wait();

            const nft2 = await nft.mint(URI);
            await nft2.wait();

            addItemtx = await marketplace.connect(deployer).addItem(1, 1);
            addItemtx.wait();
        });

        describe("addItem", () => {

            it("Should revert if collection is not added", async () => {
                await expect(marketplace.addItem(2, 1)).to.be.revertedWithCustomError(marketplace, "Marketplace__CollectionIsNotAdded");
            });

            it("Should revert if item is already added", async () => {
                await expect(marketplace.addItem(1, 1)).to.be.revertedWithCustomError(marketplace, "Marketplace__ItemAlreadyAdded");
            });

            it("Should revert if not owner of the token", async () => {
                await expect(marketplace.connect(addr1).addItem(1, 2)).to.be.revertedWithCustomError(marketplace, "Marketplace__YouAreNotTheOwnerOfThisToken");
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

            let listItemTx: ContractTransaction;
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

            await marketplace.addItem(1, 2);

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

            let buyTx: ContractTransaction;

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

    describe("Offer non-listed items", () => {

        before(async () => {
            const mint = await nft.mint(URI);
            await mint.wait();

            const add = await marketplace.addItem(1, 4);
            await add.wait();

            const list = await marketplace.listItem(3, price);
            await list.wait();

            const mint2 = await nft.mint(URI);
            await mint2.wait();

            const add2 = await marketplace.addItem(1, 5);
            await add2.wait();
        });

        describe("placeOffer", () => {
            it("Should revert if item does not exist", async () => {
                await expect(marketplace.placeOffer(10, price)).to.be.revertedWithCustomError(marketplace, "Marketplace__ItemWithThisIdDoesNotExist").withArgs(10);
            });

            it("Should revert if item is already listed", async () => {
                await expect(marketplace.placeOffer(3, price)).to.be.revertedWithCustomError(marketplace, "Marketplace__ItemAlreadyListed");
            });

            it("Should revert if price is 0", async () => {
                await expect(marketplace.placeOffer(4, 0)).to.be.revertedWithCustomError(marketplace, "Marketplace__PriceCannotBeZero");
            });

            it("Should revert if msg.sender is owner", async () => {
                await expect(marketplace.placeOffer(4, price)).to.be.revertedWithCustomError(marketplace, "Marketplace__YouCannotPlaceAnOfferOnYourOwnItem");
            });

            it("Should place offer", async () => {
                const place = await marketplace.connect(addr1).placeOffer(4, price);
                await place.wait();

                const offer = await marketplace.offers(4, addr1.address);
                expect(offer).to.deep.equal([4, nft.address, 5, deployer.address, price, false]);

                expect(await marketplace.itemOfferers(4, 0)).to.equal(addr1.address);
            });
        });

        describe("acceptOffer", () => {
            it("Should revert if offer does not exist", async () => {
                await expect(marketplace.acceptOffer(10, addr1.address)).to.be.revertedWithCustomError(marketplace, "Marketplace__OfferDoesNotExist").withArgs(10);
            });

            it("Should revert if msg.sender is not item owner", async () => {
                await expect(marketplace.connect(addr2).acceptOffer(4, addr1.address)).to.be.revertedWithCustomError(marketplace, "Marketplace__YouAreNotTheOwnerOfThisToken");
            });

            it("Should set isAccepted to true", async () => {
                const accept = await marketplace.acceptOffer(4, addr1.address);
                await accept.wait();

                const offer = await marketplace.offers(4, addr1.address);
                expect(offer).to.deep.equal([4, nft.address, 5, deployer.address, price, true]);
            });

            it("Should emit event", async () => {
                const accept = await marketplace.acceptOffer(4, addr1.address);
                await expect(accept).to.emit(marketplace, "LogOfferAccepted").withArgs(4, addr1.address);
            });
        });

        describe("claimItem", () => {

            before(async () => {
                const mint = await nft.mint(URI);
                await mint.wait();

                const add = await marketplace.addItem(1, 6);
                await add.wait();

                const offer = await marketplace.connect(addr1).placeOffer(5, price);
                await offer.wait();
            });


            it("Should revert if offer does not exist", async () => {
                await expect(marketplace.claimItem(10)).to.be.revertedWithCustomError(marketplace, "Marketplace__OfferDoesNotExist").withArgs(10);
            });

            it("Should revert if offer is not accepted", async () => {
                await expect(marketplace.connect(addr1).claimItem(5)).to.be.revertedWithCustomError(marketplace, "Marketplace__OfferIsNotAccepted").withArgs(5);
            });

            it("Should revert if price is not enough", async () => {
                const accept = await marketplace.acceptOffer(5, addr1.address);
                await accept.wait();

                await expect(marketplace.connect(addr1).claimItem(5, {value: price.div(2)})).to.be.revertedWithCustomError(marketplace, "Marketplace__NotEnoughtFunds");
            });

            it("Should claim item and pay seller", async () => {
                const selletBalanceBefore = await deployer.getBalance();

                const approve = await nft.approve(marketplace.address, 6);
                await approve.wait();

                const claim = await marketplace.connect(addr1).claimItem(5, {value: price});
                await claim.wait();

                const selletBalanceAfter = await deployer.getBalance();

                expect(selletBalanceAfter).to.be.closeTo(selletBalanceBefore.add(price), 100000000000000);                
                expect(await nft.ownerOf(6)).to.equal(addr1.address);                
                expect(await marketplace.offers(5, addr1.address)).to.deep.equal([0, ethers.constants.AddressZero, 0, ethers.constants.AddressZero, 0, false]);
            });
        });
    });

    describe("withdraw", () => {

        it("Should revert if not owner", async () => {
            await expect(marketplace.connect(addr1).withdraw()).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("Should withdraw", async () => {
            const balanceContractBefore = await ethers.provider.getBalance(marketplace.address);
            const balanceBefore = await deployer.getBalance();

            const withdrawTx = await marketplace.withdraw();
            await withdrawTx.wait();

            const balanceContractAfter = await ethers.provider.getBalance(marketplace.address);
            const balanceAfter = await deployer.getBalance();

            expect(balanceContractAfter).to.equal(0);
            expect(balanceAfter).to.be.closeTo(balanceBefore.add(balanceContractBefore), 100000000000000);
        });
    });

    describe("heleper functions", () => {

        describe("getTotalPrice", () => {

            before(async () => {
                const mint = await nft.mint(URI);
                await mint.wait();

                await marketplace.addItem(1, 3);
            });

            it("Should revert if item with this Id does not exist", async () => {
                await expect(marketplace.getTotalPrice(10)).to.be.revertedWithCustomError(marketplace, "Marketplace__ItemWithThisIdDoesNotExist").withArgs(10);
            });

            it("Should revert if item is not listed", async () => {
                await expect(marketplace.getTotalPrice(4)).to.be.revertedWithCustomError(marketplace, "Marketplace__ThisItemIsNotListedForSale").withArgs(4);
            });

            it("Should return total price", async () => {

                const list = await marketplace.listItem(4, price);
                list.wait();

                const totalPrice = await marketplace.getTotalPrice(4);

                const expectedPrice = price.mul(100 + feePercent).div(100);

                expect(totalPrice).to.equal(expectedPrice);
            });
        });


        describe("getHash", () => {

            it("Shoudl return the expected hash", async () => {
                const hash = await marketplace.getHash(nft.address, 1);

                const expectedHash = solidityKeccak256(["address", "uint256"], [nft.address, 1]);

                expect(hash).to.equal(expectedHash);
            });
        });

    });
});