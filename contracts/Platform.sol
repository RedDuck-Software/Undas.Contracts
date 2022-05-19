//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";
import "hardhat/console.sol";

contract Platform is ReentrancyGuard {

   address private owner;
   IERC20 private stakingToken;

   uint256 private timeperiodToClaim = block.timestamp + 60 seconds;//time before claiming would be available
   uint256 private weekTimePeriod = block.timestamp + 70 seconds; //7day week cycle
   uint256 private cooldownTime = 60 seconds;

   struct stackingInfo{
       uint256 amount;
       uint256 readyTimeToWithdraw;
   }

   mapping(address => stackingInfo) public balances;

   constructor(address _owner,address _token){
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
       
       if(isCompletedWeeklyCycle()){
           timeperiodToClaim = block.timestamp + 60 seconds;
           weekTimePeriod = block.timestamp + 70 seconds;
       }

   }

   function isClaimingPeriod() public view returns(bool){
        if(timeLeftUntilAllowingToClaim() == 0){
            return true;
        }
        else
        {
            return false;
        }
    }

    function isCompletedWeeklyCycle() public view returns(bool){
        if(timeLeftUntilWeeklyCycleEnds() == 0){
            return true;
        }
        else
        {
            return false;
        }
    }


    function timeLeftUntilWeeklyCycleEnds() public view returns(uint256){
        return weekTimePeriod >= 
        block.timestamp ?weekTimePeriod - block.timestamp:0;
    }

    function timeLeftUntilAllowingToClaim() public view returns(uint256){
        return timeperiodToClaim >= 
        block.timestamp ?timeperiodToClaim - block.timestamp:0;
    }  

   function lockTokens(uint _amount) external {

       if(!isClaimingPeriod()){

       stakingToken.transferFrom(msg.sender, address(this), _amount);
       balances[msg.sender].amount += _amount;

        emit Lock(msg.sender, _amount);

       }
       else{
        emit LockFailed(msg.sender,!isClaimingPeriod());
       }
       
   } 

   function unlockTokens(uint _amount) external {
       require(_amount <= balances[msg.sender].amount ,"wrong amount to unlock");

       if(!isClaimingPeriod()){
           
           balances[msg.sender].amount -= _amount;
           stakingToken.transfer(msg.sender, _amount);

           emit Unlock(msg.sender, _amount);
       }
       else{
           emit UnlockFailed(msg.sender,!isClaimingPeriod());
       }
   }

   function cooldownOnClaiming(address _staker) public view returns(uint256 timeleft){
        return balances[_staker].readyTimeToWithdraw >= 
        block.timestamp ? balances[_staker].readyTimeToWithdraw - block.timestamp:0;
    }
   
   function claimDividends() public {
       reset();

       if(isClaimingPeriod()){
       require(cooldownOnClaiming(msg.sender) == 0,"NOT READY YET");
       
       address payable staker = payable(msg.sender);

       uint256 amount = balances[staker].amount;
       uint256 contractBalance = stakingToken.balanceOf(address(this));
       uint256 payment =  amount / contractBalance;

       stakingToken.transfer(msg.sender, payment);
        //user unable to claim several times
       balances[msg.sender].readyTimeToWithdraw = block.timestamp + cooldownTime;
       
       emit DividendsPaid(msg.sender,payment);
       }
       else{
       emit FailedToClaimDividends(msg.sender,isClaimingPeriod());
       }
   }

   function getContractBalance()public view returns(uint){
       return stakingToken.balanceOf(address(this));
   } 

}

