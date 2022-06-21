//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "hardhat/console.sol";

contract PlatformV2{

   IERC20 private stakingToken;

   uint256 private timeperiodToClaim;
   uint256 private cycleTimeperiod;
   uint256 private cooldownTime;

   uint256 private stakedUndasTokens;

   uint256 public lockedEtherCashBack;
   uint256 public lockedTokenCashback;

   uint256 private resetClaimTimePeriod;
   uint256 private resetCycleTimePeriod;
   
   uint256 private contractTokenBalance;
   uint256 private contractEtherBalance;

   address private owner;
   address private marketplace;

   struct stackingInfo{
       uint256 amount;
       uint256 readyTimeToWithdraw;
   }

   mapping(address => stackingInfo) public _balancesOfLockedTokens;

   mapping (address => uint256) public balancesForCashbackInUndas;

   mapping (address => uint256) public balancesForCashbackInEth;

   //1 min = 60 / 1 day = 86400/ 1 week = 604800
   function initialize(address _owner,address _token,uint256 _timeperiodToClaim,uint256 _cycleTimeperiod,uint256 _cooldownTime) external{

       timeperiodToClaim = block.timestamp + _timeperiodToClaim;
       cycleTimeperiod = block.timestamp + _cycleTimeperiod;
       resetClaimTimePeriod = _timeperiodToClaim;
       resetCycleTimePeriod = _cycleTimeperiod;
       cooldownTime = _cooldownTime;
       stakingToken = IERC20(_token);
       owner = _owner;

   }
    
   event Lock(address sender,uint amount);

   event LockFailed(address sender,bool isAllowedToLock);

   event Unlock(address sender,uint amount);

   event UnlockFailed(address sender,bool isAllowedToUnlock);

   event DividendsPaid(address claimer,uint amount);
   
   event FailedToClaimDividends(address claimer,bool isAllowedToClaim);

   function reset() private {

       uint256 count;

       if(isClaimingPeriod()){

           if(count < 1 ) {
               contractTokenBalance = stakingToken.balanceOf(address(this));
               contractEtherBalance = address(this).balance;

               count++;//we need to take "snapshot" of balances only 1 time before dividents calculation
           }
       }
       
       if(isEndedTimeCycle()){

           timeperiodToClaim = block.timestamp + resetClaimTimePeriod;
           cycleTimeperiod = block.timestamp + resetCycleTimePeriod;

           count--;
       }
       
   }

   function setMarketplaceAddress(address _marketplace) public only(owner) {
        marketplace = _marketplace;
    }   

    function test() public returns(string memory){
        return 'test';
    }

    function addCashback(address cashbackee1, address cashbackee2, uint256 amount, bool isTokenFee) external payable only(marketplace) {

        if (isTokenFee) {
            
            stakingToken.transferFrom(cashbackee1, address(this), amount); // distribute between stakingToken vs feeToken
            stakingToken.transferFrom(cashbackee2, address(this), amount);

            balancesForCashbackInUndas[cashbackee1] += amount;
            balancesForCashbackInUndas[cashbackee2] += amount;

            lockedTokenCashback += amount * 2;

        } else {

            require (msg.value == amount * 2, "not enough value for cashback");
 
            balancesForCashbackInEth[cashbackee1] += amount;
            balancesForCashbackInEth[cashbackee2] += amount;

            lockedEtherCashBack += amount * 2;
        }
    }

   function receiveCashbackInUndas() external{

       uint256 withdrawalAmount = balancesForCashbackInUndas[msg.sender];

       require(withdrawalAmount > 0, "no funds to withdraw");
       
       balancesForCashbackInUndas[msg.sender] = 0;
       stakingToken.transfer(msg.sender,withdrawalAmount);
       lockedTokenCashback -= withdrawalAmount;

   }
   
    function receiveCashbackInEth() external{
       uint256 withdrawalAmount = balancesForCashbackInEth[msg.sender];
       
       require(withdrawalAmount > 0,"no funds to withdraw");
 
       payable(msg.sender).transfer(withdrawalAmount);
       balancesForCashbackInEth[msg.sender] = 0;
       lockedEtherCashBack -= withdrawalAmount;
   }

   modifier only(address who) {
        require(msg.sender == who, "only address fail");
        _;
   }
   
   function isClaimingPeriod()public view returns(bool){
        if(timeLeftUntilAllowingToClaim() == 0) {
            return true;
        }
        else {
            return false;
        }
    }

    function isEndedTimeCycle() public view returns(bool){
        if(timeLeftUntilTimeCycleEnds() == 0) {
            return true;
        }
        else {
            return false;
        }
    }

    function timeLeftUntilTimeCycleEnds() public view returns(uint256){
        return cycleTimeperiod >= block.timestamp ?cycleTimeperiod - block.timestamp:0;
    }

    function timeLeftUntilAllowingToClaim() public view returns(uint256){
        return timeperiodToClaim >= block.timestamp ? timeperiodToClaim - block.timestamp:0;
    }  

   function lockTokens(uint _amount) external {

       if(!isClaimingPeriod()){

            stakingToken.transferFrom(msg.sender, address(this), _amount);

            _balancesOfLockedTokens[msg.sender].amount += _amount;
            stakedUndasTokens += _amount;

            emit Lock(msg.sender, _amount);
       }
       else {
            emit LockFailed(msg.sender,!isClaimingPeriod());
       }
       
   } 

   function unlockTokens(uint _amount) external {

       require(_amount <= _balancesOfLockedTokens[msg.sender].amount ,"wrong amount to unlock");
        
       if(!isClaimingPeriod()){//rework

           _balancesOfLockedTokens[msg.sender].amount -= _amount;
           stakingToken.transfer(msg.sender, _amount);
           stakedUndasTokens -= _amount;

           emit Unlock(msg.sender, _amount);
       }
       else {
           emit UnlockFailed(msg.sender,!isClaimingPeriod());
       }
   }

   function isClaimAvailableForUser(address _staker) public view returns(uint256 timeleft){
        return _balancesOfLockedTokens[_staker].readyTimeToWithdraw >= block.timestamp ? _balancesOfLockedTokens[_staker].readyTimeToWithdraw - block.timestamp:0;
    }
   
   function claimDividends()public {
       reset();

       if(isClaimingPeriod()) {
            require(isClaimAvailableForUser(msg.sender) == 0,"NOT READY YET");
      
            address payable staker = payable(msg.sender);
            
            uint256 userAmountInUndasPool = _balancesOfLockedTokens[staker].amount;
            uint256 userAmountInEtherPool = balancesForCashbackInEth[staker];

            uint256 dividentPartOfContractBalanceInUndas = contractTokenBalance - stakedUndasTokens - lockedTokenCashback;
            uint256 dividentPartOfContractBalanceInEth = address(this).balance - lockedEtherCashBack;

            require(dividentPartOfContractBalanceInUndas > 0,"no funds for the dividents in undas on contract`s balance");
            require(dividentPartOfContractBalanceInEth > 0,"no funds for the dividents in eth on contract`s balance");

            //div cashback lock
            uint256 paymentInUndas = (userAmountInUndasPool * dividentPartOfContractBalanceInUndas) / stakedUndasTokens;
            uint256 paymentInEth = (userAmountInEtherPool * dividentPartOfContractBalanceInEth) / contractEtherBalance;

            stakingToken.transfer(msg.sender, paymentInUndas);
            payable(staker).transfer(paymentInEth);
            // address(this).transfer(msg.sender,)
            //balance contract lockedTokens 
           
            
                //user unable to claim several times
            _balancesOfLockedTokens[msg.sender].readyTimeToWithdraw = block.timestamp + cooldownTime;
       
       emit DividendsPaid(msg.sender,paymentInUndas);
    
       }
       else {

            emit FailedToClaimDividends(msg.sender,isClaimingPeriod());

       }
   }
   function getContractBalance()public view returns(uint){
        return address(this).balance;
   }
   receive() external payable{

   }
}

