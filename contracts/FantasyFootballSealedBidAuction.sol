// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.20;
import "fhevm/lib/TFHE.sol";

import "./Reencrypt.sol";
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
    
    struct Auction {
        uint256 auctionId;
        uint256 startTime;
        uint256 endTime;
        EnumerableSet.UintSet players;
        mapping(uint256 => EnumerableSet.AddressSet) playerToBettors;
        mapping(address => mapping(uint256 => Bid)) bids; // Maps bettor's address and player's ID to a Bid
        mapping(address => EnumerableSet.UintSet) bettorBids; // Maps bettor's address to an array of player IDs
        address owner;
    }

    struct ReadAuction {
        uint256 auctionId;
        uint256 startTime;
        uint256 endTime;      
        address owner;
    }       

    mapping(uint256 => Auction) private auctions;    
    EnumerableSet.UintSet private auctionsSet;

    error TooEarly(uint256 time);
    error TooLate(uint256 time);

    event AuctionCreated(uint256 auctionId);

    uint256 private auctionCounter;
    
    constructor(){
        auctionCounter = 0;
    }    

    function createAuction(uint256 startTime, uint256 endTime) public {
        auctionCounter++;   
        Auction storage auction = auctions[auctionCounter];
        auction.startTime = startTime;
        auction.endTime = endTime;
        auction.owner = msg.sender;
        auction.auctionId = auctionCounter;
        auctionsSet.add(auctionCounter);
        emit AuctionCreated(auctionCounter);
    }

    function placeBid(uint256 auctionId, uint256 playerId, bytes calldata encryptedValue) public 
        afterStart(auctionId) 
        beforeEnd(auctionId) {

            euint64 value = TFHE.asEuint64(encryptedValue);
            ebool isHigherThanZero = TFHE.gt(value, TFHE.asEuint64(0));
            require(TFHE.decrypt(isHigherThanZero), "Bid must be greater than zero");

            Auction storage auction = auctions[auctionId];

            if (auction.bids[msg.sender][playerId].exists) {
                // Update existing bid
                auction.bids[msg.sender][playerId] = Bid(value, true);
            } else {
                // Place a new bid
                auction.bids[msg.sender][playerId] = Bid(value, true);
                auction.bettorBids[msg.sender].add(playerId);
                auction.playerToBettors[playerId].add(msg.sender);
                auction.players.add(playerId);
            }
    }

    function withdrawBid(uint256 auctionId, uint256 playerId) public 
        afterStart(auctionId) 
        beforeEnd(auctionId) {

        Auction storage auction = auctions[auctionId];
        require(auction.bids[msg.sender][playerId].exists, "No bid to withdraw");

        // Remove bid
        delete auction.bids[msg.sender][playerId];

        // Update bettorBids set
        auction.bettorBids[msg.sender].remove(playerId);

        // Remove bettor from playerToBettors mapping
        auction.playerToBettors[playerId].remove(msg.sender);
    }

    function getBidsByBettor(uint256 auctionId, bytes32 publicKey, bytes calldata signature) public view 
        afterStart(auctionId) onlySignedPublicKey(publicKey, signature) returns (Offer[] memory) {

            Auction storage auction = auctions[auctionId];
            uint256 length = auction.bettorBids[msg.sender].length();
            Offer[] memory offers = new Offer[](length);

            for (uint256 i = 0; i < length; i++) {
                uint256 playerId = auction.bettorBids[msg.sender].at(i);
                euint64 playerBid = auction.bids[msg.sender][playerId].bid;
                offers[i] = Offer(playerId, TFHE.reencrypt(playerBid, publicKey, 0));
            }
            return offers;
    }

    function getBids(uint256 auctionId) public view afterStart(auctionId) afterEnd(auctionId) returns (PlayerBid[] memory) {
        Auction storage auction = auctions[auctionId];

        PlayerBid[] memory allBids = new PlayerBid[](auction.players.length());
        uint256[] memory players = auction.players.values();

        for (uint256 i = 0; i < players.length; i++) {
            uint256 playerId = players[i];
            address[] memory bettors = auction.playerToBettors[playerId].values();

            BettorOffer[] memory allBidsForPlayer = new BettorOffer[](bettors.length);

            for (uint256 j = 0; j < bettors.length; j++) {
                address bettor = bettors[j];
                euint64 bid = auction.bids[bettor][playerId].bid;
                allBidsForPlayer[i] = BettorOffer(bettor, TFHE.decrypt(bid));
            }

            allBids[i] = PlayerBid(playerId, allBidsForPlayer);
        }

        return allBids;        
    }

    function getAcutions() public view returns (ReadAuction[] memory _auctions) {
        ReadAuction[] memory readAuctions = new ReadAuction[](auctionsSet.values().length);

        for (uint256 i = 0; i < auctionsSet.length(); i++) {
            uint256 auctionId = auctionsSet.at(i);
            uint256 startTime = auctions[auctionId].startTime;
            uint256 endTime = auctions[auctionId].endTime;
            address owner = auctions[auctionId].owner;
            readAuctions[i] = ReadAuction(auctionId, startTime, endTime, owner);
        }

        return readAuctions;
    }

    function getAcution(uint256 auctionId) public view returns (ReadAuction memory _auction) {
        uint256 startTime = auctions[auctionId].startTime;
        uint256 endTime = auctions[auctionId].endTime;
        address owner = auctions[auctionId].owner;
        return ReadAuction(auctionId, startTime, endTime, owner);
    }

    modifier beforeEnd(uint256 auctionId) {

        Auction storage auction = auctions[auctionId];
        console.log(
            "beforeEnd from %s block timestamp %s %s endtime",
            msg.sender,
            block.timestamp,
            auction.endTime
        );
        if (block.timestamp > auction.endTime) {
            console.log("beforeEnd TooLate");
            revert TooLate(auction.endTime);
        }
        _;
    }

    modifier afterEnd(uint256 auctionId) {
        Auction storage auction = auctions[auctionId];
        console.log(
            "afterEnd from %s block timestamp %s %s endtime",
            msg.sender,
            block.timestamp,
            auction.endTime
        );
        if (block.timestamp <= auction.endTime){
            console.log("afterEnd TooEarly");
            revert TooEarly(auction.endTime);
        } 
        _;
    }

    modifier afterStart(uint256 auctionId) {
        Auction storage auction = auctions[auctionId];
        console.log(
            "afterStart from %s block timestamp %s %s endtime",
            msg.sender,
            block.timestamp,
            auction.startTime
        );
        if (block.timestamp < auction.startTime){
            console.log("afterStart TooEarly");
            revert TooEarly(auction.startTime);
        } 
        _;
    }
}