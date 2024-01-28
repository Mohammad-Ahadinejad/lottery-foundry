// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @title Raffle Contract
 * @author Mohammad Ahadinejad
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chanilink VRFv2
 */

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";

contract Raffle is VRFConsumerBaseV2, AutomationCompatibleInterface {
    error Raffle__NotEnoughEthSent();
    error Raffle__TransactionFailed();
    error Raffle__RaffleIsNotOpen();
    error Raffle_UpKeepNotNeeded(uint256 currentBalance, uint256 numOfPlayers, uint256 raffleState);

    /** Type Declaration */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;


    /** events */
    event EnteredRaffle(address indexed player); 
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee, 
        uint256 interval, 
        address vrfCoordinator, 
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
         )VRFConsumerBaseV2(vrfCoordinator){
        i_entranceFee = entranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value<i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if(s_raffleState!=RaffleState.OPEN){
            revert Raffle__RaffleIsNotOpen();
        }
        s_players.push(payable(msg.sender));

        emit EnteredRaffle(msg.sender);

    }

    function checkUpkeep(bytes memory /*checkData*/) public view override returns (bool upkeepNeeded, bytes memory /*performData*/){
        bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasPlayers = s_players.length>0;
        bool hasBalance = address(this).balance>0;
        upkeepNeeded = timeHasPassed && isOpen && hasPlayers && hasBalance;
        return (upkeepNeeded, "0x0");
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upKeepNeeded, ) = checkUpkeep("");
        if(!upKeepNeeded){
            revert Raffle_UpKeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );   
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit WinnerPicked(winner);
        (bool success,) = winner.call{value: address(this).balance}("");
        if(!success){
            revert Raffle__TransactionFailed();
        }
    }

    /** Getter Functions */
    
    function getEntranceFee() external view returns(uint256){
        return i_entranceFee;
    }

    function getRaffleState() external view returns(RaffleState){
        return s_raffleState;
    }


    function getPlayer(uint256 index) external view returns(address){
        return s_players[index];
    }

    function getRecentWinner() external view returns(address){
        return s_recentWinner;
    }

    function getLastTimestamp() external view returns(uint256){
        return s_lastTimeStamp;
    }

    function getNumberOfPlayers() external view returns(uint256){
        return s_players.length;
    }

}