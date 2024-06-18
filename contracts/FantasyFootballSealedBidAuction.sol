// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.20;

import "./Reencrypt.sol";

import "fhevm/lib/TFHE.sol";
import "hardhat/console.sol";

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

contract FantasyFootballSealedBidAuction is Reencrypt {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    struct Bid {
        euint64 bid;
        bool exists;
    }

    struct Offer {
        uint256 playerId;
        bytes encBid;
    }

    struct BettorOffer {
        address bettor;
        uint64 bid;
    }

    struct PlayerBid {
        uint256 playerId;
        BettorOffer[] bettors;
    }

    struct Round {
        uint256 startTime;
        uint256 endTime;
        EnumerableSet.UintSet players;
        mapping(uint256 => EnumerableSet.AddressSet) playerToBettors;
        mapping(address => mapping(uint256 => Bid)) bids; // Maps bettor's address and player's ID to a Bid
        mapping(address => EnumerableSet.UintSet) bettorBids; // Maps bettor's address to an array of player IDs
    }
    
    struct Auction {
        uint256 auctionId;
        address owner;
        Round[] rounds;
    }

    struct ReadAuction {
        uint256 auctionId;
        address owner;
    }

    struct ReadRound {
        uint256 startTime;
        uint256 endTime;      
    }

    error AuctionDoesNotExist(uint256 auctionId);
    error TooEarly(uint256 time);
    error TooLate(uint256 time);
    event AuctionCreated(uint256 auctionId);

    uint256 private auctionCounter;
    mapping(uint256 => Auction) private auctions;    
    EnumerableSet.UintSet private auctionsSet;
    
    constructor(){
        auctionCounter = 0;
    }    

    function createAuction() public {
        auctionCounter++;   
        Auction storage auction = auctions[auctionCounter];
        auction.owner = msg.sender;
        auction.auctionId = auctionCounter;
        auctionsSet.add(auctionCounter);
        emit AuctionCreated(auctionCounter);
    }

    function addRound(uint256 _auctionId, uint256 _startTime, uint256 _endTime) public isValidAuction(_auctionId) {
        Auction storage auction = auctions[_auctionId];

        // Ensure the auction exists
        require(auction.owner != address(0), "Auction does not exist");

        // Ensure the new round does not collide with existing rounds
        for (uint256 i = 0; i < auction.rounds.length; i++) {
            Round storage round = auction.rounds[i];
            require(
                (_startTime < round.startTime && _endTime <= round.startTime) || 
                (_startTime >= round.endTime && _endTime > round.endTime),
                "Round times collide with an existing round"
            );
        }

        // Add the new round
        auction.rounds.push();
        uint256 newRoundIndex = auction.rounds.length - 1;
        Round storage newRound = auction.rounds[newRoundIndex];
        newRound.startTime = _startTime;
        newRound.endTime = _endTime;
    }

    function getActiveRound(uint256 _auctionId) internal view isValidAuction(_auctionId) returns (Round storage) {
        Auction storage auction = auctions[_auctionId];

        // Get the current timestamp
        uint256 currentTime = block.timestamp;

        // Iterate over the rounds
        for (uint256 i = 0; i < auction.rounds.length; i++) {
            Round storage round = auction.rounds[i];
            if (currentTime >= round.startTime && currentTime <= round.endTime) {
                // The current timestamp is within the start and end times of this round
                return round;
            }
        }

        // No active round
        revert("No active round at the moment");
    }

    function getCurrentRound(uint256 _auctionId) public view returns (ReadRound memory) {
        Round storage round = getActiveRound(_auctionId);
        return ReadRound(round.startTime, round.endTime);
    }

    function placeBid(uint256 auctionId, uint256 playerId, bytes calldata encryptedValue) public {            

            euint64 value = TFHE.asEuint64(encryptedValue);
            ebool isHigherThanZero = TFHE.gt(value, TFHE.asEuint64(0));
            require(TFHE.decrypt(isHigherThanZero), "Bid must be greater than zero");

            Auction storage auction = auctions[auctionId];
            uint256 currentTime = block.timestamp;

            for (uint256 i = 0; i < auction.rounds.length; i++) {
                Round storage round = auction.rounds[i];
                if(currentTime > round.endTime){
                    require(!EnumerableSet.contains(round.players, playerId), "Player already has a bid");
                }                
            }

            // Get the current round
            Round storage currentRound = getActiveRound(auctionId);

            if (currentRound.bids[msg.sender][playerId].exists) {
                // Update existing bid
                currentRound.bids[msg.sender][playerId] = Bid(value, true);
            } else {
                // Place a new bid
                currentRound.bids[msg.sender][playerId] = Bid(value, true);
                currentRound.bettorBids[msg.sender].add(playerId);
                currentRound.playerToBettors[playerId].add(msg.sender);
                currentRound.players.add(playerId);
            }
    }

    function withdrawBid(uint256 auctionId, uint256 playerId) public {

        // Get the current round
        Round storage currentRound = getActiveRound(auctionId);
        require(currentRound.bids[msg.sender][playerId].exists, "No bid to withdraw for the current round");

        // Remove bid
        delete currentRound.bids[msg.sender][playerId];

        // Update bettorBids set
        currentRound.bettorBids[msg.sender].remove(playerId);

        // Remove bettor from playerToBettors mapping
        currentRound.playerToBettors[playerId].remove(msg.sender);
    }

    function getBidsByBettor(uint256 auctionId, bytes32 publicKey, bytes calldata signature) public view 
        onlySignedPublicKey(publicKey, signature) returns (Offer[] memory) {

            // Get the current round
            Round storage currentRound = getActiveRound(auctionId);

            uint256 length = currentRound.bettorBids[msg.sender].length();
            Offer[] memory offers = new Offer[](length);

            for (uint256 i = 0; i < length; i++) {
                uint256 playerId = currentRound.bettorBids[msg.sender].at(i);
                euint64 playerBid = currentRound.bids[msg.sender][playerId].bid;
                offers[i] = Offer(playerId, TFHE.reencrypt(playerBid, publicKey, 0));
            }
            return offers;
    }

    function getBids(uint256 auctionId) public view returns (PlayerBid[][] memory) {
        Auction storage auction = auctions[auctionId];

        // Get the current timestamp
        uint256 currentTime = block.timestamp;
        uint256 roundsLenght = 0;

        for (uint256 r = 0;  r < auction.rounds.length; r++) {
            Round storage round = auction.rounds[r];
            if (currentTime > round.endTime) {
                roundsLenght++;
            }
        }

        PlayerBid[][] memory allBids = new PlayerBid[][](roundsLenght);
        uint256 k = 0;

        for (uint256 r = 0;  r < auction.rounds.length; r++) {
            Round storage round = auction.rounds[r];

            if (currentTime > round.endTime) {

                PlayerBid[] memory allRoundBids = new PlayerBid[](round.players.length());
                uint256[] memory players = round.players.values();

                for (uint256 i = 0; i < players.length; i++) {
                    uint256 playerId = players[i];            
                    address[] memory bettors = round.playerToBettors[playerId].values();

                    BettorOffer[] memory allBidsForPlayer = new BettorOffer[](bettors.length);

                    for (uint256 j = 0; j < bettors.length; j++) {
                        address bettor = bettors[j];
                        euint64 bid = round.bids[bettor][playerId].bid;             
                        allBidsForPlayer[j] = BettorOffer(bettor, TFHE.decrypt(bid));
                    }

                    allRoundBids[i] = PlayerBid(playerId, allBidsForPlayer);
                }

                allBids[k] = allRoundBids;
                k++;                
            }
        }

        return allBids;               
    }

    function getAcutions() public view returns (ReadAuction[] memory _auctions) {
        ReadAuction[] memory readAuctions = new ReadAuction[](auctionsSet.values().length);

        for (uint256 i = 0; i < auctionsSet.length(); i++) {
            uint256 auctionId = auctionsSet.at(i);
            address owner = auctions[auctionId].owner;
            readAuctions[i] = ReadAuction(auctionId, owner);
        }

        return readAuctions;
    }

    function getAcution(uint256 auctionId) public view returns (ReadAuction memory _auction) {
        address owner = auctions[auctionId].owner;
        return ReadAuction(auctionId, owner);
    }

    modifier isValidAuction(uint256 _auctionId) {
        Auction storage auction = auctions[_auctionId];
        if (auction.owner == address(0)) {
            console.log("isValidAuction AuctionDoesNotExist");
            revert AuctionDoesNotExist(_auctionId);
        }
        _;
    }

    // modifier beforeEnd(uint256 auctionId) {
    //     Auction storage auction = auctions[auctionId];
    //     Round storage round = getActiveRound(auctionId);
    //     if (block.timestamp > round.endTime) {
    //         console.log("beforeEnd TooLate");
    //         revert TooLate(round.endTime);
    //     }
    //     _;
    // }

    // modifier afterEnd(uint256 auctionId) {
    //     Auction storage auction = auctions[auctionId];
    //     Round storage round = getActiveRound(auctionId);
    //     if (block.timestamp <= round.endTime){
    //         console.log("afterEnd TooEarly");
    //         revert TooEarly(round.endTime);
    //     } 
    //     _;
    // }

    // modifier afterStart(uint256 auctionId) {
    //     Auction storage auction = auctions[auctionId];       
    //      Round storage round = getActiveRound(auctionId);
    //     if (block.timestamp < round.startTime){
    //         console.log("afterStart TooEarly");
    //         revert TooEarly(round.startTime);
    //     } 
    //     _;
    // }
}