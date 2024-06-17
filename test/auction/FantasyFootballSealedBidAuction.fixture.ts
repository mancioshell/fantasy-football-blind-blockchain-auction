import { ethers } from "hardhat";

import type { FantasyFootballSealedBidAuction } from "../../types";
import { getSigners } from "../signers";

export async function deployAuctionFixture(): Promise<FantasyFootballSealedBidAuction> {
  const signers = await getSigners();

  const contractFactory = await ethers.getContractFactory("FantasyFootballSealedBidAuction");
  const contract = await contractFactory.connect(signers.alice).deploy();
  await contract.waitForDeployment();

  return contract;
}
