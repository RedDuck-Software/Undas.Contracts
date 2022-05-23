//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "hardhat/console.sol";

contract Platform{

   IERC20 private stakingToken;

   uint256 private timeperiodToClaim;
   uint256 private cycleTimeperiod;
   uint256 private cooldownTime;
   uint256 private ContractBalanceForDividends;
   uint256 public lockedEtherCashBack;
   uint256 public lockedTokenCashback;
   address private owner;
   address private marketplace;

   struct stackingInfo{
       uint256 amount;
       uint256 readyTimeToWithdraw;
   }

   mapping(address => stackingInfo) public _balancesOfLockedTokens;
   mapping (address => uint256) public balancesForCashbackInUndas;
   mapping (address => uint256) public balancesForCashbackInEth;

   //1 min = 60 / 1 day = 86400/ 1 week = 604 800
   constructor(address _owner,address _token,
   uint256 _timeperiodToClaim,uint256 _cycleTimeperiod,uint256 _cooldownTime){

       timeperiodToClaim = block.timestamp + _timeperiodToClaim;
       cycleTimeperiod = block.timestamp + _cycleTimeperiod;
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
       if(isEndedTimeCycle()){
           timeperiodToClaim = block.timestamp + 60 seconds;
           cycleTimeperiod = block.timestamp + 70 seconds;
       }
   }

   function setMarketplaceAddress(address _marketplace) public only(owner) {
        marketplace = _marketplace;
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

   function receiveCashbackInUndas(address cashbackee) external only(marketplace) {
       uint256 withdrawalAmount = balancesForCashbackInUndas[cashbackee];
       require(withdrawalAmount > 0, "no funds to withdraw");
       
       balancesForCashbackInUndas[cashbackee] = 0;
       stakingToken.transfer(cashbackee,withdrawalAmount);
       lockedTokenCashback -= withdrawalAmount;
   }
   
    function receiveCashbackInEth(address cashbackee) external only(marketplace) {
       uint256 withdrawalAmount = balancesForCashbackInEth[cashbackee];
       require(withdrawalAmount > 0,"no funds to withdraw");
    //    require(lockedEtherCashBack < address(this).balance,"not enough funds on contract balance");
    //    require(isClaimingPeriod() == true,"you can claim cashback only at 'claiming period'");       
       payable(cashbackee).transfer(withdrawalAmount);
       balancesForCashbackInEth[cashbackee] = 0;
       lockedEtherCashBack -= withdrawalAmount;
   }

   modifier only(address who) {
        require(msg.sender == who, "only address fail");
        _;
   }
   
   function isClaimingPeriod()public view returns(bool){
        if(timeLeftUntilAllowingToClaim() == 0){
            return true;
        }
        else
        {
            return false;
        }
    }

    function isEndedTimeCycle() public view returns(bool){
        if(timeLeftUntilTimeCycleEnds() == 0){
            return true;
        }
        else
        {
            return false;
        }
    }

    function timeLeftUntilTimeCycleEnds() public view returns(uint256){
        return cycleTimeperiod >= 
        block.timestamp ?cycleTimeperiod - block.timestamp:0;
    }

    function timeLeftUntilAllowingToClaim() public view returns(uint256){
        return timeperiodToClaim >= 
        block.timestamp ?timeperiodToClaim - block.timestamp:0;
    }  

   function lockTokens(uint _amount) external {

       if(!isClaimingPeriod()){
       stakingToken.transferFrom(msg.sender, address(this), _amount);
       _balancesOfLockedTokens[msg.sender].amount += _amount;
       ContractBalanceForDividends += _amount;

       emit Lock(msg.sender, _amount);

       }else{
        emit LockFailed(msg.sender,!isClaimingPeriod());
       }
       
   } 

   function unlockTokens(uint _amount) external {
       require(_amount <= _balancesOfLockedTokens[msg.sender].amount ,"wrong amount to unlock");
        
       if(!isClaimingPeriod()){
           _balancesOfLockedTokens[msg.sender].amount -= _amount;
           stakingToken.transfer(msg.sender, _amount);
           ContractBalanceForDividends -= _amount;
           emit Unlock(msg.sender, _amount);
       }
       else{
           emit UnlockFailed(msg.sender,!isClaimingPeriod());
       }
   }

   function isClaimAvailableForUser(address _staker) public view returns(uint256 timeleft){
        return _balancesOfLockedTokens[_staker].readyTimeToWithdraw >= 
        block.timestamp ? _balancesOfLockedTokens[_staker].readyTimeToWithdraw - block.timestamp:0;
    }
   
   function claimDividends()public {
       reset();
       
       if(isClaimingPeriod()){
       require(isClaimAvailableForUser(msg.sender) == 0,"NOT READY YET");
       
       address payable staker = payable(msg.sender);

       uint256 amount = _balancesOfLockedTokens[staker].amount;
       uint256 payment =  amount / ContractBalanceForDividends;//todo normal formula

       stakingToken.transfer(msg.sender, payment);
        //user unable to claim several times
       _balancesOfLockedTokens[msg.sender].readyTimeToWithdraw = block.timestamp + cooldownTime;
       
       emit DividendsPaid(msg.sender,payment);
    
       }
       else{

       emit FailedToClaimDividends(msg.sender,isClaimingPeriod());

       }
   }
}

