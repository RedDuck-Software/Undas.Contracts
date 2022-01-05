// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from 'hardhat'

async function main() {
  const tokenFactory = await ethers.getContractFactory('OnlyOne')
  const token = await (await tokenFactory.deploy()).deployed()

  // We get the contract to deploy
  const Marketplace = await ethers.getContractFactory('Marketplace')
  const marketplace = await Marketplace.deploy()

  const NFT = await ethers.getContractFactory('MyToken')
  const nft = await NFT.deploy()

  await marketplace.deployed()
  await nft.deployed()

  console.log('Marketplace deployed to:', marketplace.address)
  console.log('NFT deployed to:', nft.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})
