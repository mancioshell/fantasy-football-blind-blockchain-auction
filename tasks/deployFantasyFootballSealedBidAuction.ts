import { task } from "hardhat/config";
import type { TaskArguments } from "hardhat/types";

task("task:deploySealedBidAuction").setAction(async function (taskArguments: TaskArguments, { ethers }) {
  const signers = await ethers.getSigners();
  const fantasyFootballSealedBidAuctionFactory = await ethers.getContractFactory("FantasyFootballSealedBidAuction");
  const encryptedFantasyFootballSealedBidAuction = await fantasyFootballSealedBidAuctionFactory
    .connect(signers[0])
    .deploy();
  await encryptedFantasyFootballSealedBidAuction.waitForDeployment();
  console.log(
    "FantasyFootballSealedBidAuction deployed to: ",
    await encryptedFantasyFootballSealedBidAuction.getAddress(),
  );
});
