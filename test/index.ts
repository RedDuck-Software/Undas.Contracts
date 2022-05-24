import { expect, use } from "chai";
import { ethers } from "hardhat";
import RouterFactory from "../node_modules/@uniswap/v2-periphery/build/UniswapV2Router02.json";
import UniswapFactory from '../node_modules/@uniswap/v2-core/build/UniswapV2Factory.json'
import { IERC20__factory} from "../typechain/factories/IERC20__factory";
import IUniswapV2Pair from '../node_modules/@uniswap/v2-core/build/IUniswapV2Pair.json'
import { platform } from "os";
import { Marketplace, UndasGeneralNFT } from "../typechain";
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
    Platform = await platform.deploy(owner.address,OnlyOneToken.address,518400,604800,172800);
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

   await Platform.connect(owner).setMarketplaceAddress(NftMarketplace.address);
  //  await Platform.connect(owner).setMarketplaceAddress(NftMarketplace.address);

   //approving undasToken for liqudiity pool
   await OnlyOneToken.connect(owner).approve(Router.address, ethers.utils.parseUnits("20", 18));

   //adding tokens to participants
   await OnlyOneToken.connect(owner).transfer(user.address,ethers.utils.parseUnits("20",18))
   await OnlyOneToken.connect(owner).transfer(buyer.address,ethers.utils.parseUnits("20",18))
   await OnlyOneToken.connect(owner).transfer(buyer2.address,ethers.utils.parseUnits("20",18))
   //approving tokens to the market
   await OnlyOneToken.connect(user).approve(NftMarketplace.address,ethers.utils.parseUnits("10",18));
   await OnlyOneToken.connect(buyer).approve(NftMarketplace.address,ethers.utils.parseUnits("10",18));
   await OnlyOneToken.connect(buyer2).approve(NftMarketplace.address,ethers.utils.parseUnits("10",18));

   await OnlyOneToken.connect(user).approve(Platform.address,ethers.utils.parseUnits("10",18));
   await OnlyOneToken.connect(buyer).approve(Platform.address,ethers.utils.parseUnits("5",18));
   await OnlyOneToken.connect(buyer2).approve(Platform.address,ethers.utils.parseUnits("5",18));
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
    //nft for renting 1
    await Nft.connect(user).safeMintGeneral(
      user.address,
     "test",
     "test nft2",
     "https://img.png"
    );
    //nft for renting 2
    await Nft.connect(user).safeMintGeneral(
    user.address,
   "test",
   "test nft3",
   "https://img.png"
    );


    await Nft.connect(user).setApprovalForAll(NftMarketplace.address, true); 
    
    expect(await NftMarketplace.connect(user).bidExternal(
      Nft.address,
      0,
      ethers.utils.parseUnits("2.0","ether"),
      0,
      {
        value: ethers.utils.parseUnits("0.04","ether"),//fee 2*2/100
      }
  )).to.emit(NftMarketplace,'Listed')

  
    const latestBlock = await hre.ethers.provider.getBlock("latest")
  
    expect(await NftMarketplace.connect(user).bidAndStake(
      Nft.address,
      1,
      ethers.utils.parseUnits("2","ether"),//collateral(zalog)
      ethers.utils.parseUnits("0.1","ether"),
      latestBlock.timestamp + 1209600,//1 day;
      ethers.utils.parseUnits("2.0","ether"),//price
      0,
      {
        value: ethers.utils.parseUnits("0.08","ether"),//fee 2000*2/100
      }
    )).to.emit(NftMarketplace,'Listed')
  
    expect(await NftMarketplace.connect(user).bidAndStake(
      Nft.address,
      2,
      ethers.utils.parseUnits("2","ether"),//collateral(zalog)
      ethers.utils.parseUnits("0.1","ether"),
      latestBlock.timestamp + 1209600,//1 day;
      ethers.utils.parseUnits("2.0","ether"),//price
      1,
      {
        value: ethers.utils.parseUnits("0.04","ether"),//fee 2000*2/100
      }
    )).to.emit(NftMarketplace,'Listed')



  });
  
  it("it should allow to buy nft and to get", async function () {

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
        buyer.address
       )).to.emit(NftMarketplace,"Sale")      


    //buyer should manualy take his eth back

    expect(await NftMarketplace.connect(buyer2).cancelListingOffer(
      0
    )).to.emit(NftMarketplace,"ListingOffer").to.changeEtherBalance(buyer2,ethers.utils.parseUnits("1.5","ether"))


})

it("it allows to rent rentable nft",async function (){

  expect(await NftMarketplace.connect(buyer).rentNFT(
    0,
    0,
    {
    value:ethers.utils.parseUnits("2.12","ether") // collateral + premium + (premium * _premiumFeePercentage / 100)
    }

  ))
    //   console.log(ethers.utils.formatUnits(await NftMarketplace.getContractBalance(),"ether"))
    // console.log(ethers.utils.formatUnits(await Platform.getContractBalance(),"ether"))
})

it("it allows to make offer to rent nft and allows to accept it",async function (){

  //buyer offers 1 eth as collar + 0,5 eth as premium
  expect(await NftMarketplace.connect(buyer).stakingOffer(
    0,
    ethers.utils.parseUnits("1","ether"),
    ethers.utils.parseUnits("0.5","ether"),
    {
      value:ethers.utils.parseUnits("1.6","ether") // collateral + premium + (premium * _premiumFeePercentage / 100)
    }
    )).to.emit(NftMarketplace,'StakingOffered').to.changeEtherBalance(buyer,
      ethers.utils.parseUnits("-1.6","ether"))

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
      value:ethers.utils.parseUnits("1.6","ether")//collarate+premium
    }
    )).to.emit(NftMarketplace,'StakingOffered').to.changeEtherBalance(buyer,
      ethers.utils.parseUnits("-1.6","ether"))

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

    })
it("it allows to lock /unlock token during locking period/and not allows to lock them during claiming one",async function () {

    expect(await Platform.connect(user).lockTokens(20000000)).to.emit(Platform,"Lock")  
    expect(await Platform.connect(user).unlockTokens(20000000)).to.emit(Platform,"Unlock")

    await expect(Platform.connect(user).unlockTokens(20000000)).to.be.revertedWith("wrong amount to unlock")

    await Platform.provider.send("evm_increaseTime", [518400])
    await Platform.provider.send("evm_mine")

    expect(await Platform.connect(user).lockTokens(20000000)).to.emit(Platform,"LockFailed")

    
})

it("it allows to pay premium/ and allows to pay it extra time",async function () {

  expect(await NftMarketplace.connect(buyer).rentNFT(
        0,
        1,
        {
        value:ethers.utils.parseUnits("2.12","ether") // collateral + premium + (premium * _premiumFeePercentage / 100)
        }
  ))

    await Nft.connect(buyer).setApprovalForAll(
      NftMarketplace.address,
      true
    )
   
    await expect(NftMarketplace.connect(user).claimCollateral(0))
    .to.be.revertedWith("premiums have been paid and deadline is yet to be reached");
    
    await NftMarketplace.connect(buyer).payPremium(0,1,{
      value:ethers.utils.parseUnits("0.1","ether")
    })

    await NftMarketplace.provider.send("evm_increaseTime", [604800])//1  week past
    await NftMarketplace.provider.send("evm_mine")

    await expect(NftMarketplace.connect(buyer).payPremium(0,1,{
      value:ethers.utils.parseUnits("0.1","ether")
    })).to.be.revertedWith("too many payments")


    // console.log(await NftMarketplace.paymentsDue(0))

    NftMarketplace.connect(buyer).stopRental(0);

})
it("it allows to claim dividends",async function() {

      await Platform.connect(buyer).lockTokens(500000000000000)
      await Platform.connect(user).lockTokens(300000000000000)
      await Platform.connect(buyer2).lockTokens(400000000000000)
      
        expect(await NftMarketplace.connect(buyer).rentNFT(
          0,//stakiing id 
          1,
          {
          value:ethers.utils.parseUnits("2.12","ether") // collateral + premium + (premium * _premiumFeePercentage / 100)
          }
        ))

        expect(await NftMarketplace.connect(buyer2).rentNFT(
            1,
            1,
            {
            value:ethers.utils.parseUnits("2.12","ether") // collateral + premium + (premium * _premiumFeePercentage / 100)
            }
        ))

        await Platform.provider.send("evm_increaseTime", [518400])//setting time to claiming period 
        await Platform.provider.send("evm_mine")

        console.log("user undas balance before claiming " + ethers.utils.formatUnits(await OnlyOneToken.balanceOf(user.address),18));
        console.log("user eth balance before claiming " + ethers.utils.formatUnits(await user.getBalance(),"ether"))

        expect(await Platform.connect(user).claimDividends()).to.emit(Platform,"DividendsPaid").to.changeEtherBalance(user, ethers.utils.parseUnits("0.01", "ether"))

        console.log("user undas balance after claiming " + ethers.utils.formatUnits(await OnlyOneToken.balanceOf(user.address),18));
        console.log("user eth balance after claiming " + ethers.utils.formatUnits(await user.getBalance(),"ether"))
        
        await expect(Platform.connect(user).claimDividends()).to.be.revertedWith("NOT READY YET")

        console.log("buyer2 undas balance before claiming " + ethers.utils.formatUnits(await OnlyOneToken.balanceOf(buyer2.address),18));
        console.log("buyer2 eth balance before claiming " + ethers.utils.formatUnits(await buyer2.getBalance(),18))
      
        expect(await Platform.connect(buyer2).claimDividends()).to.emit(Platform,"DividendsPaid")

        console.log("buyer2 undas balance after claiming " + ethers.utils.formatUnits(await OnlyOneToken.balanceOf(buyer2.address),18));
        console.log("buyer2 eth balance after claiming " + ethers.utils.formatUnits(await buyer2.getBalance(),18))

        await expect(Platform.connect(buyer2).claimDividends()).to.be.revertedWith("NOT READY YET")




})

})
