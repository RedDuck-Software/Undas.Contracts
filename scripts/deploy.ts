
const { ethers,upgrades } = require("hardhat");

  async function main() {
      const tokenFactory = await ethers.getContractFactory("OnlyOne");
      const token = await (await tokenFactory.deploy()).deployed();
    
      const nftFactory = await ethers.getContractFactory("UndasGeneralNFT");
      const nft = await (await nftFactory.deploy()).deployed();
  
      const PlatformFactory = await ethers.getContractFactory("Platform")
      const platform = await upgrades.deployProxy(PlatformFactory,[
        "0x1DEA6eF29D05437E5721C38Fd0f916CDf1a93a24",
        token.address,
        "86400",
        "604800",
        "86400"
      ],{
        initializer : "initialize"
      })
      await platform.deployed()
      
      const Marketplace = await ethers.getContractFactory("Marketplace")
      const marketplace = await upgrades.deployProxy(Marketplace,[
            platform.address,
            token.address,
            '0x1DEA6eF29D05437E5721C38Fd0f916CDf1a93a24',
            10000,
            10000,
            "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
            "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"],
          {initializer : "initialize"})
      await marketplace.deployed()
      console.log('platform',platform.address)
      console.log('marketplace',marketplace.address)
      console.log('nft',nft.address)
      console.log('erc20 token',token.address)


  }
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
