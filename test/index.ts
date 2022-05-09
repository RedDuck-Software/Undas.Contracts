import { expect } from "chai";
import { ethers } from "hardhat";

describe("NftMarketplaceTest", function () {
  it("should create/sell nft", async function () {
    const [owner, whitelist, user] = await ethers.getSigners();

    const onlyOneToken = await ethers.getContractFactory("OnlyOne");
    const OnlyOneToken = await onlyOneToken.deploy();
    await OnlyOneToken.deployed();

    const platform = await ethers.getContractFactory("Staking");
    const Platform = await platform.deploy(OnlyOneToken.address);
    await Platform.deployed();
    
    const nft = await ethers.getContractFactory("UndasGeneralNFT");
    const Nft = await nft.deploy();
    await Nft.deployed();

    const nftMarketplace = await ethers.getContractFactory(
      "Marketplace",
      owner
    );
    const NftMarketplace = await nftMarketplace.deploy(
      Platform.address,
      OnlyOneToken.address,
      whitelist.address,
      20,
      10
    );
    await NftMarketplace.deployed();
    console.log("marketplace address :" + NftMarketplace.address);
    console.log("erc20 deployed to" + OnlyOneToken.address);
    console.log("platform deployed to" + Platform.address);
    console.log("nft deployed to" + Nft.address);

    await Nft.connect(user).safeMintGeneral(
      user.address,
      "test",
      "test nft",
      "https://img.png"
    );
    await Nft.connect(user).setApprovalForAll(NftMarketplace.address, true);
    const value = ethers.utils.parseUnits("0.1", "ether");
    expect(
      await NftMarketplace.connect(user).bid(Nft.address, 0, "200", { 
        value: value, 
      })
    ).to.emit(NftMarketplace, "Listed");
  });

  it("should revert with error", async function () {
    const [owner, whitelist, user] = await ethers.getSigners();

    const onlyOneToken = await ethers.getContractFactory("OnlyOne");
    const OnlyOneToken = await onlyOneToken.deploy();
    await OnlyOneToken.deployed();

    const platform = await ethers.getContractFactory("Staking");
    const Platform = await platform.deploy(OnlyOneToken.address);
    await Platform.deployed();

    const nft = await ethers.getContractFactory("UndasGeneralNFT");
    const Nft = await nft.deploy();
    await Nft.deployed();

    const nftMarketplace = await ethers.getContractFactory(
      "Marketplace",
      owner
    );
    const NftMarketplace = await nftMarketplace.deploy(
      Platform.address,
      OnlyOneToken.address,
      whitelist.address,
      20,
      10
    );
    await NftMarketplace.deployed();
    console.log("marketplace address :" + NftMarketplace.address);
    console.log("erc20 deployed to" + OnlyOneToken.address);
    console.log("platform deployed to" + Platform.address);
    console.log("nft deployed to" + Nft.address);

    await Nft.connect(user).safeMintGeneral(
        user.address,
        "test",
        "test nft",
        "https://img.png"
    );

    await Nft.connect(user).setApprovalForAll(NftMarketplace.address, true);
    const value = ethers.utils.parseUnits("0.01", "ether");
    await expect(
        NftMarketplace.connect(user).bid(Nft.address, 0, "200", {
          value: value,
        })
    ).to.be.revertedWith("bidFee");
  });
  it("should allow to buy nft", async function () {
    const [owner, whitelist, user, buyer] = await ethers.getSigners();

    const onlyOneToken = await ethers.getContractFactory("OnlyOne");
    const OnlyOneToken = await onlyOneToken.deploy();
    await OnlyOneToken.deployed();

    const platform = await ethers.getContractFactory("Staking");
    const Platform = await platform.deploy(OnlyOneToken.address);
    await Platform.deployed();

    const nft = await ethers.getContractFactory("UndasGeneralNFT");
    const Nft = await nft.deploy();
    await Nft.deployed();

    const nftMarketplace = await ethers.getContractFactory(
        "Marketplace",
        owner
    );
    const NftMarketplace = await nftMarketplace.deploy(
        Platform.address,
        OnlyOneToken.address,
        whitelist.address,
        20,
        10
    );
    await NftMarketplace.deployed();
    console.log("marketplace address :" + NftMarketplace.address);
    console.log("erc20 deployed to" + OnlyOneToken.address);
    console.log("platform deployed to" + Platform.address);
    console.log("nft deployed to" + Nft.address);

    await Nft.connect(user).safeMintGeneral(
        user.address,
        "test",
        "test nft",
        "https://img.png"
    );
    await Nft.connect(user).setApprovalForAll(NftMarketplace.address, true);
    const value = ethers.utils.parseUnits("0.1", "ether");

    await NftMarketplace.connect(user).bid(Nft.address, 0, "200", {
      value: value,
    });
    expect(
        await NftMarketplace.connect(buyer).buyToken(0, { value: "200" })
    ).changeEtherBalances([buyer, user], [-200, 200]);
  });
  // setApproval bug
  // totalSupply bug
});
