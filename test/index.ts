import { expect, use } from "chai";
import { ethers } from "hardhat";
import RouterFactory from "../node_modules/@uniswap/v2-periphery/build/UniswapV2Router02.json";
import UniswapFactory from '../node_modules/@uniswap/v2-core/build/UniswapV2Factory.json'
import { IERC20__factory} from "../typechain/factories/IERC20__factory";
import IUniswapV2Pair from '../node_modules/@uniswap/v2-core/build/IUniswapV2Pair.json'
import { platform } from "os";
const hre = require("hardhat");

describe("NftMarketplaceTest", function () {
  let owner;
  let whitelist;
  let OnlyOneToken;
  let Platform;
  let Nft;
  let NftMarketplace;
  let Uniswap;
  let Router;
  let WEth;
  let user;
  let buyer;
  let buyer2;
  beforeEach(async function () {
    [owner, whitelist,user,buyer,buyer2] = await ethers.getSigners();
    this.timeout(30000)//too many async
    const onlyOneToken = await ethers.getContractFactory("OnlyOne",owner);
    OnlyOneToken = await onlyOneToken.deploy();
    await OnlyOneToken.deployed();

    let wrappedEth = await IERC20__factory.connect(
      "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
    owner);
    WEth = await wrappedEth.deployed();

    const platform = await ethers.getContractFactory("Platform");
    Platform = await platform.deploy(owner.address,OnlyOneToken.address);
    await Platform.deployed();

    const nft = await ethers.getContractFactory("UndasGeneralNFT",owner);
    Nft = await nft.deploy();
    await Nft.deployed();
    
    Uniswap = await new ethers.Contract(
      "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",
      UniswapFactory.abi,
      ethers.provider
  );
    
    Router = await new ethers.Contract(
     "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
     RouterFactory.abi,
     ethers.provider
   );
   
   const nftMarketplace = await ethers.getContractFactory(
      "Marketplace",
      owner
    );
    NftMarketplace = await nftMarketplace.deploy(
      Platform.address,
      OnlyOneToken.address,
      whitelist.address,
      20,
      10,
      "0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f",//UniswapFactory mainnet addr
      WEth.address //wETH mainnet addr
    );
   await NftMarketplace.deployed();
      
  //  await Platform.connect(owner).setMarketplaceAddress(NftMarketplace.address);

   //approving undasToken for liqudiity pool
   await OnlyOneToken.connect(owner).approve(Router.address, ethers.utils.parseUnits("20", 18));

   //adding tokens to participants
   await OnlyOneToken.connect(owner).transfer(user.address,ethers.utils.parseUnits("20",18))
   await OnlyOneToken.connect(owner).transfer(buyer.address,ethers.utils.parseUnits("20",18))
   //approving tokens to the market
   await OnlyOneToken.connect(user).approve(NftMarketplace.address,ethers.utils.parseUnits("20",18));
   await OnlyOneToken.connect(buyer).approve(NftMarketplace.address,ethers.utils.parseUnits("20",18));
   //adding liqudity on pair undas/WEth
    await Router.connect(owner).addLiquidityETH( //1:1
        OnlyOneToken.address,
        ethers.utils.parseUnits("20", 18),
        2,
        ethers.utils.parseUnits("20","ether"),
        owner.address,
        Date.now() + 3600,
        {
          value:ethers.utils.parseUnits("20","ether")
        }
      )
    //minting NFT on user addr
    await Nft.connect(user).safeMintGeneral(
        user.address,
       "test",
       "test nft",
       "https://img.png"
     );
    //nft for renting
     await Nft.connect(user).safeMintGeneral(
      user.address,
     "test2",
     "test nft2",
     "https://img.png"
   );
    await Nft.connect(user).setApprovalForAll(NftMarketplace.address, true); 
    //creating nft

    expect(await NftMarketplace.connect(user).bidExternal(
      Nft.address,
      0,
      ethers.utils.parseUnits("2.0","ether"),
      1,
      {
        value: ethers.utils.parseUnits("0.04","ether"),//fee 2000*2/100
      }
  )).to.emit(NftMarketplace,'Listed').to.changeEtherBalance(user,
    ethers.utils.parseUnits("-0.04","ether"))
    //rentable nft
    expect(await NftMarketplace.connect(user).bidAndStake(
      Nft.address,
      1,
      ethers.utils.parseUnits("2","ether"),//collateral(zalog)
      ethers.utils.parseUnits("0.1","ether"),
      Date.now() + 3600,//1 day;
      ethers.utils.parseUnits("2.0","ether"),//price
      1,
      {
        value: ethers.utils.parseUnits("0.04","ether"),//fee 2000*2/100
      }
    )).to.emit(NftMarketplace,'Listed')
  });
  
  it("it should allow to buy", async function () {

     expect(await NftMarketplace.connect(buyer).buyToken(
        0,    
        {
          value: ethers.utils.parseUnits("2.0","ether"),
        }
    )).to.emit(NftMarketplace,"Sale")
  
  });

  it("it should allow owner to cancel nft bid", async function () {

    await expect(NftMarketplace.connect(buyer).cancel(0)).to.be.revertedWith('Only seller can cancel listing')
    expect(await NftMarketplace.connect(user).cancel(0)).to.emit(NftMarketplace,'CancelBid')
    expect(await NftMarketplace.isBuyable(0)).to.be.eq(false)

  });

  it("it should allow buyer to make lising offer to buy nft and seller to accept it", async function () {

    //buyer making listing offer and sending 1 eth on marketplace acc
    expect(await NftMarketplace.connect(buyer).listingOffer(
       0,    
       {
         value: ethers.utils.parseUnits("1","ether"),
       }
      )).to.emit(NftMarketplace,"ListingOffer").to.changeEtherBalance(
        buyer,ethers.utils.parseUnits("-1","ether"));
    
    expect(await NftMarketplace.isBuyable(0)).to.be.eq(true)

    //seller accepting buyer's offer
    expect(await NftMarketplace.connect(user).acceptListingOffer(
       0,    
       buyer.address
      )).
      to.emit(NftMarketplace,'ListingOfferCompleted').
      to.changeEtherBalance(user,ethers.utils.parseUnits("1","ether"))

    expect(await NftMarketplace.isBuyable(0)).to.be.eq(false)

// console.log(ethers.utils.formatUnits(await buyer.getBalance()) + ' / ' + ethers.utils.formatUnits(await user.getBalance()))
});


it("it allows listing offer maker to take their eth back,if seller accepted other offer",async function (){
  
    //buyer  making offer
    expect(await NftMarketplace.connect(buyer).listingOffer(
      0,    
      {
        value: ethers.utils.parseUnits("1","ether"),
      }
      )).to.emit(NftMarketplace,"ListingOffer").to.changeEtherBalance(
      buyer,ethers.utils.parseUnits("-1","ether"));

    //buyer2 making offer as well
    expect(await NftMarketplace.connect(buyer2).listingOffer(
        0,    
        {
          value: ethers.utils.parseUnits("1.5","ether"),
        }
        )).to.emit(NftMarketplace,"ListingOffer").to.changeEtherBalance(
          buyer2,ethers.utils.parseUnits("-1.5","ether"));

    //seller accepting offer of buyer2
    expect(await NftMarketplace.connect(user).acceptListingOffer(
        0,    
        buyer2.address
       )).to.emit(NftMarketplace,"Sale")      

    //buyer should manualy take his eth back
    expect(await NftMarketplace.connect(buyer).cancelListingOffer(
        0
      )).to.changeEtherBalance(buyer,ethers.utils.parseUnits("1","ether"))   
  
})

it("it allows to rent rentable nft ",async function (){
  expect(await NftMarketplace.connect(buyer).rentNFT(
    0,
    1,
    {
    value:ethers.utils.parseUnits("2.1","ether")
    }
  ))
})

it("it allows to make offer to rent nft and allows to accept it",async function (){
  //buyer offers 1 eth as collar + 0,5 eth as premium
  expect(await NftMarketplace.connect(buyer).stakingOffer(
    0,
    ethers.utils.parseUnits("1","ether"),
    ethers.utils.parseUnits("0.5","ether"),
    {
      value:ethers.utils.parseUnits("1.5","ether")//collarate+premium
    }
    )).to.emit(NftMarketplace,'StakingOffered').to.changeEtherBalance(buyer,
      ethers.utils.parseUnits("-1.5","ether"))

  expect(await NftMarketplace.connect(user).acceptStakingOffer(
    0,
    buyer.address,
    1
  )).to.emit(NftMarketplace,'StakingOfferAccepted').to.changeEtherBalance(user,
      ethers.utils.parseUnits("0.5","ether"))

})

it("it allows to stop renting nft and give collateral back to buyer ",async function (){
  expect(await NftMarketplace.connect(buyer).stakingOffer(
    0,
    ethers.utils.parseUnits("1","ether"),
    ethers.utils.parseUnits("0.5","ether"),
    {
      value:ethers.utils.parseUnits("1.5","ether")//collarate+premium
    }
    )).to.emit(NftMarketplace,'StakingOffered').to.changeEtherBalance(buyer,
      ethers.utils.parseUnits("-1.5","ether"))

  expect(await NftMarketplace.connect(user).acceptStakingOffer(
    0,
    buyer.address,
    1
  )).to.emit(NftMarketplace,'StakingOfferAccepted').to.changeEtherBalance(user,
    ethers.utils.parseUnits("0.5","ether"))
    
    //new temporary owner of nft should approve it at "undsaGeneralNft" contract
    await Nft.connect(buyer).setApprovalForAll(
      NftMarketplace.address,
      true
    )

  expect(await NftMarketplace.connect(buyer).stopRental(
    0,
     )).to.changeEtherBalance(buyer,
      ethers.utils.parseUnits("1","ether"))

      // console.log('after stopping rental ' + ethers.utils.formatUnits(await buyer.getBalance()) + ' / ' + ethers.utils.formatUnits(await user.getBalance()))

      // console.log(ethers.utils.formatUnits(await Platform.connect(owner).tokenCashback(buyer.address)))
      // console.log(ethers.utils.formatUnits(await Platform.connect(owner).tokenCashback(owner.address)))

      // console.log(await Platform.connect(owner).tokenCashback(user))
})

});
