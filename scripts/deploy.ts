// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from 'hardhat'
import { UndasGeneralNFT } from '../typechain';

const mintBunch = async (tokenContract: UndasGeneralNFT, count: number, to: string) => {
  for (let i = 0; i < count; i++)
    await tokenContract.safeMintGeneral(to, `NFT number ${i}`, `NFT name ${i}`, "data:image/png;base64,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");
}

async function main() {
  const [owner] = await ethers.getSigners();

  const tokenFactory = await ethers.getContractFactory('OnlyOne')
  const token = await (await tokenFactory.deploy()).deployed()

  const platformFactory = await ethers.getContractFactory('Platform')
  const platform = await (await platformFactory.deploy(token.address)).deployed()

  const marketplaceFactory = await ethers.getContractFactory('Marketplace')
  const marketplace = await marketplaceFactory.deploy(platform.address, token.address, owner.address, 10000, 10000);

  const nftFactory = await ethers.getContractFactory('UndasGeneralNFT')
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
