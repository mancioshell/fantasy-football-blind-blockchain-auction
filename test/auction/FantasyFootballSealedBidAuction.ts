import { expect } from "chai";
import { ethers, network } from "hardhat";

import { createInstances } from "../instance";
import { getSigners, initSigners } from "../signers";
import { deployAuctionFixture } from "./FantasyFootballSealedBidAuction.fixture";

describe("FantasyFootballSealedBidAuction", function () {
  before(async function () {
    await initSigners();
    this.signers = await getSigners();
  });

  beforeEach(async function () {
    const contract = await deployAuctionFixture();
    this.contractAddress = await contract.getAddress();
    console.log("contractAddress", this.contractAddress);
    this.auction = contract;
    this.instances = await createInstances(this.contractAddress, ethers, this.signers);
  });

  it("should create an auction", async function () {
    const startDate = new Date();
    const startDateTimestamp = Math.floor(startDate.getTime() / 1000);

    const currentDate = new Date();
    currentDate.setSeconds(currentDate.getSeconds() + 20);
    const endDateTimestamp = Math.floor(currentDate.getTime() / 1000);

    const tx = await this.auction.createAuction(startDateTimestamp, endDateTimestamp);
    await tx.wait();

    const auctions = await this.auction.getAcutions();
    const auction = auctions[0];
    const createdAuction = await this.auction.getAcution(auction.auctionId);

    expect(createdAuction.startTime).to.equal(startDateTimestamp);
    expect(createdAuction.endTime).to.equal(endDateTimestamp);
  });

  it("should place multiple bids and retrives the values", async function () {
    const startDate = new Date();
    const startDateTimestamp = Math.floor(startDate.getTime() / 1000);

    const currentDate = new Date();
    currentDate.setSeconds(currentDate.getSeconds() + 20);
    const endDateTimestamp = Math.floor(currentDate.getTime() / 1000);

    let tx = await this.auction.createAuction(startDateTimestamp, endDateTimestamp);
    await tx.wait();

    await ethers.provider.send("evm_increaseTime", [2]);
    await ethers.provider.send("evm_mine"); // this will mine a new block with the updated timestamp

    const auctions = await this.auction.getAcutions();
    const auction = auctions[0];
    const createdAuction = await this.auction.getAcution(auction.auctionId);

    const bobBids = [
      { playerId: 1, bid: 18 },
      { playerId: 2, bid: 29 },
    ];

    const auctionWithBob = this.auction.connect(this.signers.bob);

    for (const bobBid of bobBids) {
      const encryptedBobBid = this.instances.bob.encrypt64(bobBid.bid);
      tx = await auctionWithBob.placeBid(createdAuction.auctionId, bobBid.playerId, encryptedBobBid);
      await tx.wait();
    }

    const auctionWithAlice = this.auction.connect(this.signers.alice);
    const encryptedAliceBid = this.instances.alice.encrypt64(5);
    tx = await auctionWithAlice.placeBid(createdAuction.auctionId, bobBids[0].playerId, encryptedAliceBid);
    await tx.wait();

    const tokenBob = this.instances.bob.getPublicKey(this.contractAddress);

    const encryptedBids = await auctionWithBob.getBidsByBettor(
      createdAuction.auctionId,
      tokenBob?.publicKey,
      tokenBob?.signature,
    );

    expect(encryptedBids.length).to.equal(bobBids.length);

    for (const [index, encryptedBid] of encryptedBids.entries()) {
      const playerId = parseInt(encryptedBid[0]);
      const bobBidResult = this.instances.bob.decrypt(this.contractAddress, encryptedBid[1]);

      expect(bobBidResult).to.equal(bobBids[index].bid);
      expect(playerId).to.equal(bobBids[index].playerId);
    }
  });

  it("should replace a bid", async function () {
    const startDate = new Date();
    const startDateTimestamp = Math.floor(startDate.getTime() / 1000);

    const currentDate = new Date();
    currentDate.setSeconds(currentDate.getSeconds() + 20);
    const endDateTimestamp = Math.floor(currentDate.getTime() / 1000);

    let tx = await this.auction.createAuction(startDateTimestamp, endDateTimestamp);
    await tx.wait();

    await ethers.provider.send("evm_increaseTime", [2]);
    await ethers.provider.send("evm_mine"); // this will mine a new block with the updated timestamp

    const auctions = await this.auction.getAcutions();
    const auction = auctions[0];
    const createdAuction = await this.auction.getAcution(auction.auctionId);

    let bobBids = [
      { playerId: 1, bid: 18 },
      { playerId: 2, bid: 29 },
    ];

    const updatedBobBid = 25;
    const updatedPlayerId = 2;

    const auctionWithBob = this.auction.connect(this.signers.bob);

    for (const bobBid of bobBids) {
      const encryptedBobBid = this.instances.bob.encrypt64(bobBid.bid);
      tx = await auctionWithBob.placeBid(createdAuction.auctionId, bobBid.playerId, encryptedBobBid);
      await tx.wait();
    }

    const auctionWithAlice = this.auction.connect(this.signers.alice);
    const encryptedAliceBid = this.instances.alice.encrypt64(5);
    tx = await auctionWithAlice.placeBid(createdAuction.auctionId, bobBids[0].playerId, encryptedAliceBid);
    await tx.wait();

    const encryptedBobBid = this.instances.bob.encrypt64(updatedBobBid);
    tx = await auctionWithBob.placeBid(createdAuction.auctionId, updatedPlayerId, encryptedBobBid);
    await tx.wait();

    bobBids = bobBids.map((bid) => (bid.playerId === updatedPlayerId ? { ...bid, bid: updatedBobBid } : bid));

    const tokenBob = this.instances.bob.getPublicKey(this.contractAddress);

    const encryptedBids = await auctionWithBob.getBidsByBettor(
      createdAuction.auctionId,
      tokenBob?.publicKey,
      tokenBob?.signature,
    );

    expect(encryptedBids.length).to.equal(bobBids.length);

    for (const [index, encryptedBid] of encryptedBids.entries()) {
      const playerId = parseInt(encryptedBid[0]);
      const bobBidResult = this.instances.bob.decrypt(this.contractAddress, encryptedBid[1]);

      expect(bobBidResult).to.equal(bobBids[index].bid);
      expect(playerId).to.equal(bobBids[index].playerId);
    }
  });

  it("should withdraw a bid", async function () {
    const startDate = new Date();
    const startDateTimestamp = Math.floor(startDate.getTime() / 1000);

    const currentDate = new Date();
    currentDate.setSeconds(currentDate.getSeconds() + 30);
    const endDateTimestamp = Math.floor(currentDate.getTime() / 1000);

    let tx = await this.auction.createAuction(startDateTimestamp, endDateTimestamp);
    await tx.wait();

    await ethers.provider.send("evm_increaseTime", [2]);
    await ethers.provider.send("evm_mine"); // this will mine a new block with the updated timestamp

    const auctions = await this.auction.getAcutions();
    const auction = auctions[0];
    const createdAuction = await this.auction.getAcution(auction.auctionId);

    let bobBids = [
      { playerId: 1, bid: 18 },
      { playerId: 2, bid: 29 },
    ];

    const auctionWithBob = this.auction.connect(this.signers.bob);

    for (const bobBid of bobBids) {
      const encryptedBobBid = this.instances.bob.encrypt64(bobBid.bid);
      tx = await auctionWithBob.placeBid(createdAuction.auctionId, bobBid.playerId, encryptedBobBid);
      await tx.wait();
    }

    const auctionWithAlice = this.auction.connect(this.signers.alice);
    const encryptedAliceBid = this.instances.alice.encrypt64(5);
    tx = await auctionWithAlice.placeBid(createdAuction.auctionId, bobBids[0].playerId, encryptedAliceBid);
    await tx.wait();

    tx = await auctionWithBob.withdrawBid(createdAuction.auctionId, bobBids[0].playerId);
    await tx.wait();

    bobBids = bobBids.filter((bid) => bid.playerId !== bobBids[0].playerId);

    const tokenBob = this.instances.bob.getPublicKey(this.contractAddress);

    const encryptedBids = await auctionWithBob.getBidsByBettor(
      createdAuction.auctionId,
      tokenBob?.publicKey,
      tokenBob?.signature,
    );

    expect(encryptedBids.length).to.equal(bobBids.length);

    for (const [index, encryptedBid] of encryptedBids.entries()) {
      const playerId = parseInt(encryptedBid[0]);
      const bobBidResult = this.instances.bob.decrypt(this.contractAddress, encryptedBid[1]);

      expect(bobBidResult).to.equal(bobBids[index].bid);
      expect(playerId).to.equal(bobBids[index].playerId);
    }
  });

  it("should get all bids after end", async function () {
    const startDate = new Date();
    const startDateTimestamp = Math.floor(startDate.getTime() / 1000);

    const currentDate = new Date();
    currentDate.setSeconds(currentDate.getSeconds() + 50);
    const endDateTimestamp = Math.floor(currentDate.getTime() / 1000);

    let tx = await this.auction.createAuction(startDateTimestamp, endDateTimestamp);
    await tx.wait();

    await ethers.provider.send("evm_increaseTime", [2]);
    await ethers.provider.send("evm_mine"); // this will mine a new block with the updated timestamp

    const auctions = await this.auction.getAcutions();
    const auction = auctions[0];
    const createdAuction = await this.auction.getAcution(auction.auctionId);

    let bobBids = [
      { playerId: 1, bid: 18 },
      { playerId: 2, bid: 29 },
    ];

    let aliceBids = [
      { playerId: 1, bid: 2 },
      { playerId: 3, bid: 44 },
    ];

    const auctionWithBob = this.auction.connect(this.signers.bob);

    for (const bobBid of bobBids) {
      const encryptedBobBid = this.instances.bob.encrypt64(bobBid.bid);
      tx = await auctionWithBob.placeBid(createdAuction.auctionId, bobBid.playerId, encryptedBobBid);
      await tx.wait();
    }

    const auctionWithAlice = this.auction.connect(this.signers.alice);

    for (const aliceBid of aliceBids) {
      const encryptedAliceBid = this.instances.alice.encrypt64(aliceBid.bid);
      tx = await auctionWithAlice.placeBid(createdAuction.auctionId, aliceBid.playerId, encryptedAliceBid);
      await tx.wait();
    }

    await ethers.provider.send("evm_increaseTime", [50]);
    await ethers.provider.send("evm_mine"); // this will mine a new block with the updated timestamp

    const bids = await auctionWithBob.getBids(createdAuction.auctionId);

    expect(bids.length).to.equal(bobBids.length + aliceBids.length);

    for (const [index, bid] of bids.entries()) {
      console.log("bid", bid);
    }
  });
});
