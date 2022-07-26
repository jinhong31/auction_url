// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Participant.sol";


import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

abstract contract IApplicationPrimary {
    function blockParticipant(
        uint256 isActive,
        address manager,
        bool blockedType_
    ) external;
}

abstract contract CellSlotsInterface {
    function mint(address slotOwner, uint256 rank) external payable virtual;

    function burn(uint256 slotId) external payable virtual;
}

/**
 * @title Primary
 * @dev This is a primary contract for cellchain slot candle auction. 
        Participants deploy their own participant contract through this contract.
        This starts and finishes auction, and selects the winner participant and mint slot NFT for it.
 */
contract AuctionPrimary{
    struct Auction {
        Participant[] deployedParticipants;
        mapping(address => uint256) managerIndex;
        uint256 maxRange;
        uint256 minimalCellSlotPrice;
        uint256 auctionState; // 0 - NO, 1 - pending, 2 - on auction, 3 - finished, 4 - winner selected
    }

    struct BidToken {
        address tokenAddress;
        uint256 rate;
        bool isLpToken;
        uint256 ageRank;
    }

    IApplicationPrimary applicationPrimary;

    // Array with all token addresses, used for enumeration
    BidToken[] private _bidTokens;

    // Mapping from token address to position in the _bidTokens array
    mapping(address => uint256) private _allTokensIndex;

    Participant[][] public passedAuctions;
    address[] public winnerParticipants;

    Auction[2] public auctions;
    uint8 private actIdx = 0;

    address public owner;

    uint256 public auctionStartTime = 0;
    uint256 public auctionEndTime = 0;
    uint256 public auctionEndPhaseStartTime = 0;

    uint256 public auctionFinishTime = 0;

    bool public isPrimary = true;

    CellSlotsInterface public cellSlots;

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
    * @param cellSlotsAddress_ Address of the cell slot NFT handle contract.
    */
    constructor(address cellSlotsAddress_)
    {
        owner = msg.sender;
        cellSlots = CellSlotsInterface(cellSlotsAddress_);
        _bidTokens.push(
            BidToken({
                tokenAddress: 0x26c8AFBBFE1EBaca03C2bB082E69D0476Bffe099,
                rate: 1,
                isLpToken: false,
                ageRank: 0
            })
        );
    }

    function blockParticipant(
        uint256 isActive,
        address manager,
        bool blockedType_
    ) external onlyOwner {
        require(isActive == 0 || isActive == 1, "Invalid isActive param.");
        uint256 idx = isActive == 0 ? actIdx : 1 - actIdx;
        uint256 index = auctions[idx].managerIndex[manager];
        uint256 lastIndex = auctions[idx].deployedParticipants.length - 1;
        auctions[idx].deployedParticipants[index].blocked(blockedType_);
        auctions[idx].deployedParticipants[index] = auctions[idx]
            .deployedParticipants[lastIndex];
        auctions[idx].deployedParticipants.pop();
        applicationPrimary.blockParticipant(isActive, manager, blockedType_);
    }

    /**
     * @notice A participant deploys it's own contract to participate in the auction.
     * @param _name name of the participant project
     * @param _type type of the project it could be primary or community.
     * @param _metaURI additional info for project like token name, bio for project, icon uri on ipfs etc.
     */
    function createParticipant(
        uint256 isActive,
        address _participant,
        string memory _name,
        bool _type,
        uint256 range,
        string memory _metaURI,
        bool hasGovernance,
        string memory token_name,
        uint256 max_supply,
        uint256 max_reward,
        uint256 mag
    ) private {
        require(isActive == 0 || isActive == 1, "Invalid isActive param.");
        uint256 idx = isActive == 0 ? actIdx : 1 - actIdx;
        Auction storage auction = auctions[idx];
        Participant newParticipant = new Participant(
            _participant,
            _name,
            _type,
            range / 100,
            range % 100,
            _metaURI
        );
        if (hasGovernance) {
            newParticipant.setGovernanceTokenInfo(
                token_name,
                max_supply,
                max_reward,
                mag
            );
        }
        if (auction.auctionState == 2) {
            newParticipant.startAuction();
        }
        auction.managerIndex[_participant] = auction
            .deployedParticipants
            .length;
        auction.deployedParticipants.push(newParticipant);
    }

    /**
     * @notice
     */

    /**
     * @notice returns current deployed participant contracts
     * @return array of participant contract addresses
     *
     */
    function getDeployedPartipants(uint256 isActive)
        external
        view
        returns (Participant[] memory)
    {
        require(isActive == 0 || isActive == 1, "Invalid isActive param.");
        uint256 idx = isActive == 0 ? actIdx : 1 - actIdx;
        Auction storage auction = auctions[idx];
        return auction.deployedParticipants;
    }

    /**
     * @notice starts candle auction for particular contract. only owner can do this.
     * @param startTime_ This is the time when the auction starts. Contributers can vote their funds from this time.
     * @param endPhaseStartTime_ From this time, the auction can be finished. Nobody knows. It will be determined randomly after auction has finished.
     */
    function startAuction(uint256 startTime_, uint256 endPhaseStartTime_)
        external
        onlyOwner
    {
        Auction storage auction = auctions[actIdx];
        require(
            auction.deployedParticipants.length > 0,
            "No participants for the auction"
        );
        auctionStartTime = startTime_;
        auctionEndPhaseStartTime = endPhaseStartTime_;
        auction.auctionState = 2;
        uint256 i;
        for (i = 0; i < auction.deployedParticipants.length; i++)
            auction.deployedParticipants[i].startAuction();
    }

    /**
   * @notice auction has finished and it doesn't accept votes anymore.
      It will determine the auction close time retroactively by choosing random moment during the ending phase duration.
   * @param endTime_ Time that the auction was ended. The real finished time will be determined randomly between endPhaseTime and endTime.
   */
    function finishVoting(uint256 endTime_) external onlyOwner {
        require(
            auctionStartTime != 0 && auctionEndPhaseStartTime != 0,
            "The auction did not started"
        );
        require(
            endTime_ >= auctionEndPhaseStartTime,
            "It can be only finished during auction ending phase time."
        );
        auctionEndTime = endTime_;
        auctions[actIdx].auctionState = 3;
        getRandomNumber();
    }

    

    function mintSlotTo(address ownerAddress, uint256 rank) public {
        address slotOwner = ownerAddress;
        cellSlots.mint(slotOwner, rank);
    }

    // /**
    //  * @notice Release the loaned slot. This slot will be free and can be auctioned again.
    //  */
    // function releaseSlot() external onlyOwner {
    //   require(slotOwner != address(0), "The slot is not loaned now.");
    //   slotOwner = address(0);
    // }

    /**
     * @notice Transfer the ownership of the primary contract.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Owner address should not be null");
        owner = newOwner;
    }

    /**
     * @notice Change the cellslots contract address
     */
    function setCellSlotsAddress(address newAddress) external onlyOwner {
        require(newAddress != address(0), "Address could not be null");
        cellSlots = CellSlotsInterface(newAddress);
    }

    /**
     *
     */
    function setMinimalCellSlotPrice(uint256 isActive, uint256 price)
        external
        onlyOwner
    {
        uint256 idx = isActive == 0 ? actIdx : 1 - actIdx;
        require(price > 0, "The price should be larger than 0.");
        auctions[idx].minimalCellSlotPrice = price;
    }

    function auctionFinished(address winnerAddress) private {
        Participant[] storage deployedParticipants = auctions[actIdx]
            .deployedParticipants;
        passedAuctions.push(deployedParticipants);
        winnerParticipants.push(winnerAddress);
        clearAuction(actIdx);
    }

    function createActiveAuction(uint256 range, uint256 price)
        external
        onlyOwner
    {
        require(
            auctions[actIdx].auctionState == 0,
            "There is an active auction"
        );
        if (auctions[1 - actIdx].auctionState == 1) actIdx = 1 - actIdx;
        else {
            auctions[actIdx].auctionState = 1;
            auctions[actIdx].minimalCellSlotPrice = price;
            auctions[actIdx].maxRange = range;
        }
    }

    function createFutureAuction(uint256 range, uint256 price)
        external
        onlyOwner
    {
        require(
            auctions[1 - actIdx].auctionState == 0,
            "There is a future auction"
        );
        auctions[1 - actIdx].auctionState = 1;
        auctions[1 - actIdx].minimalCellSlotPrice = price;
        auctions[1 - actIdx].maxRange = range;
    }

    function clearAuction(uint256 idx) private {
        uint256 i;
        Auction storage auction = auctions[idx];
        for (i = 0; i < auction.numOfApplicants; i++) {
            delete auction.applications[auction.applicants[i]];
        }
        delete auctions[idx];
    }

    function getPassedAuctionCount() external view returns (uint256) {
        return passedAuctions.length;
    }

    function getPassedAuction(uint256 index)
        external
        view
        returns (Participant[] memory)
    {
        return passedAuctions[index];
    }

    function getWinnerParticipants() external view returns (address[] memory) {
        return winnerParticipants;
    }

    function burnSlot(uint256 tokenId) external onlyOwner {
        cellSlots.burn(tokenId);
    }

    function withdrawFund(
        address participant_,
        address recepient_,
        address tokenAddress
    ) external onlyOwner {
        Participant(participant_).withdrawFund(recepient_, tokenAddress);
    }

    /**
     * @notice Add a biddable token to the list. Bidders can also bid to the auction with this token.
     */
    function addBidToken(
        address tokenAddress,
        uint256 rate,
        bool isLpToken,
        uint256 ageRank
    ) external onlyOwner {
        _allTokensIndex[tokenAddress] = _bidTokens.length;
        _bidTokens.push(
            BidToken({
                tokenAddress: tokenAddress,
                rate: rate,
                isLpToken: isLpToken,
                ageRank: ageRank
            })
        );
    }

    /**
     * @notice Remove a biddable token from the list. Bidders can't bid to the auction with this token.
     */
    function removeBidToken(address tokenAddress) external onlyOwner {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _bidTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenAddress];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last added token is removed) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement
        BidToken storage lastToken = _bidTokens[lastTokenIndex];

        _bidTokens[tokenIndex] = lastToken; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastToken.tokenAddress] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenAddress];
        _bidTokens.pop();
    }

    function getTokenIndexByAddress(address tokenAddress)
        external
        view
        returns (uint256)
    {
        return _allTokensIndex[tokenAddress];
    }

    function getBidTokenByIndex(uint256 index)
        external
        view
        returns (
            address,
            uint256,
            bool,
            uint256
        )
    {
        require(index < _bidTokens.length, "Index out of size");
        return (
            _bidTokens[index].tokenAddress,
            _bidTokens[index].rate,
            _bidTokens[index].isLpToken,
            _bidTokens[index].ageRank
        );
    }

    /**
    @notice Add bid to a specific project manually by owener.
   */
    // function addBidToProject(address participant, address token, uint256 amount, address voter) external onlyOwner {

    // }
}

//TODO: Able to claim back funds after lock period
//Minimal Score
//TODO: there could be no winner.
//TODO: Claim back funds after auction finished
//TODO: Claim back PLEDGE funds after 2 weeks of apply
//TODO: Add bid manually (score)
//TODO: providing LP-tokens after auction wins
