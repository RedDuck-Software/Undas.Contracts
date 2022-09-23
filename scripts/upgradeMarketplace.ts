
  const PROXY = '0xA24a7E2beed00E65C6B44006C7cfd6c7E8409c6A';

  async function main2() {
      console.log('upgrading....')
      const MarketplaceV3 = await ethers.getContractFactory("MarketplaceMVPV3")
      await upgrades.upgradeProxy(PROXY,MarketplaceV3)
      console.log('upgraded')

  }
main2().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});