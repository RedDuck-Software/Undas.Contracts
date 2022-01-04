// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";

async function main() {
  const tokenFactory = await ethers.getContractFactory("OnlyOne");
  const token = await (await tokenFactory.deploy()).deployed();

  const platformFactory = await ethers.getContractFactory("Platform");
  const platform = await (await platformFactory.deploy(token.address)).deployed();

  const baseBidFee = ethers.utils.parseEther("0.0001");

  const marketplaceFactory = await ethers.getContractFactory("Marketplace");
  const marketplace = await (await marketplaceFactory.deploy(platform.address, baseBidFee)).deployed();

  console.log("\nPlatform deployed to: ", platform.address);
  console.log("OnlyOne token deployed to: ", token.address);
  console.log("Marketplace deployed to: ", marketplace.address, '\n');
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
