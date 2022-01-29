// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from 'hardhat'
import { TestNFT } from '../typechain';

const mintBunch = async (tokenContract: TestNFT, count: number, to: string) => {
  for (let i = 0; i < count; i++)
    await tokenContract.safeMint(to);
}

async function main() {
  const [owner] = await ethers.getSigners();

  const tokenFactory = await ethers.getContractFactory('OnlyOne')
  const token = await (await tokenFactory.deploy()).deployed()

  const platformFactory = await ethers.getContractFactory('Platform')
  const platform = await (await platformFactory.deploy(token.address)).deployed()

  const marketplaceFactory = await ethers.getContractFactory('Marketplace')
  const marketplace = await marketplaceFactory.deploy(platform.address, token.address, owner.address, 10000, 10000);

  const nftFactory = await ethers.getContractFactory('TestNFT')
  const nft = await (await nftFactory.deploy()).deployed();


  const initNftMintAmount = 10;
  await mintBunch(nft, initNftMintAmount, owner.address);

  console.log('Platform deployed to:', platform.address)
  console.log('Marketplace deployed to:', marketplace.address)
  console.log('NFT deployed to:', nft.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
