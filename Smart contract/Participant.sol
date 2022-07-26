// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface ERC20TokenInterface {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address owner) external returns (uint256);
}

interface PrimaryInterface {
    function getTokenIndexByAddress(address tokenAddress) external view returns (uint8);
    function getBidTokenByIndex(uint8 index) external view returns (address, uint256, bool, uint256);
}

/**
 * @title Participant
 * @dev This is a participant contract for cellchain slot candle auction.
 */
contract Participant {
    
    struct Fund_event {
        address voter;
        uint256 voteTime;
        address token;
        uint256 value;
        uint256 score;
        uint8 start_range;
        uint8 end_range;
    }

    struct Fund {
        uint256 score;
        uint8 start_range;
        uint8 end_range;
        mapping(address=>uint256) amounts;
        address[] fundTokens;
    }

    struct BidToken {
        address tokenAddress;
        uint256 rate;
        bool isLpToken;
        uint256 ageRank;
    }

    /**
    * @notice describes whether it's type is private or community. true - community, false - private
    */
    bool public participant_type = false;
    uint public start_block;
    uint public end_block;

    bool public isBlocked = false;
    bool public blockedType = false;

    /**
    * @notice Hold all funds that voters voted.
    */
    Fund_event[] public funds;

    uint256 public voteCount = 0; // Number of votes until  the end of auction opening duration
    mapping(address => Fund) private fundsByVoter; // during auction duration
    uint256 public totalScore = 0;
    address[] public voters;
    uint256 public numberOfVoters = 0;
    
    address public manager;
    address public primary;
    string public name;
    string public metaURI;
    uint public state; // 0 - pending, 1 - active, 3 - governance

    uint256 public auctionFinishTime = 0;
    bool private _finalized = false; // if the auction is finished (this means the secret end.)
    uint256 public finalTotalScore = 0;
    mapping(address => Fund) public finalFundByVoter;
    address[] public finalVoters;
    mapping(address => uint256) voterIndexes;
    uint256 public finalNumOfVoters = 0;

    bool public hasGovernance = false;
    uint256 public totalGoverns = 0;
    mapping(address => uint256) public governsByVoter;
    string public GT_Name;
    uint256 public MAX_SUPPLY = 0;
    uint256 public MAX_REWARD = 0;
    uint public MAG = 1;
    uint256 public estimatedTotalGoverns = 0;

    modifier onlyManager() {
      require(msg.sender == manager);
      _;
    }
    
    modifier onlyPrimary() {
        require(msg.sender == primary);
        _;
    }
        
    modifier afterEnd() {
        require (state > 1, 'Unable before the auction ends');
        _;
    }

    /**
    * @notice initialize the project with it's manager, project name, project type and link to additional metainfo.
    * @param creator The address to the manager(creator) of this project
    */
    constructor(address creator, string memory _name, bool _type, uint st_range, uint end_range, string memory _metaURI) {
        manager = creator;
        primary = msg.sender;
        name = _name;
        metaURI = _metaURI;
        participant_type = _type;
        start_block = st_range;
        end_block = end_range;
        hasGovernance = false;
    }

    function setGovernanceTokenInfo(string memory token_name, uint256 m_supply, uint256 m_reward, uint256 mag) external onlyPrimary {
        hasGovernance = true;
        GT_Name = token_name;
        MAX_SUPPLY = m_supply;
        MAX_REWARD = m_reward;
        MAG = mag;
    }

    /**
    * @notice Vote funds to the project. if it is a private project, only the manager can vote to it.
    */
    function vote(uint8 st_range, uint8 end_range, uint256 amount, address tokenAddress) external {
        require(state == 1, "You can only vote while the auction is in active.");
        require(st_range <= end_range, "End time must be bigger than start time");
        require(st_range >= start_block, "Start range must be larger then the project's.");
        require(end_range <= end_block, "End range must be lower then the project's.");
        require(amount > 0, "You should vote at least more than 0");
        if (participant_type == false) {
            require(msg.sender == manager, "This is private project. You can't vote to this project.");
        }
        uint8 tokenIndex = PrimaryInterface(primary).getTokenIndexByAddress(tokenAddress);
        require(tokenIndex != 0, 'Invalid Token Address');
        (,uint rate,,) = PrimaryInterface(primary).getBidTokenByIndex(tokenIndex);
        Fund storage _userFund = fundsByVoter[msg.sender];
        require((_userFund.end_range == 0) || (st_range <= _userFund.end_range && end_range >= _userFund.start_range), "Can not have split range");
        uint256 score = amount * (end_range - st_range + 1) * rate;
        if (hasGovernance == true && MAX_SUPPLY != 0) {
            require(estimatedTotalGoverns+score*MAG <= MAX_REWARD, 'Reached to MAX_REWARD');
            estimatedTotalGoverns += score*MAG;
        }

        ERC20TokenInterface(tokenAddress).transferFrom(msg.sender, address(this), amount);

        if (_userFund.score == 0) {
            voters.push(msg.sender);
            numberOfVoters++;
        }

        _userFund.score += score;
        if (_userFund.amounts[tokenAddress] == 0) {
            _userFund.fundTokens.push(tokenAddress);
        }
        _userFund.amounts[tokenAddress] += amount;
        if (st_range < _userFund.start_range) _userFund.start_range = st_range;
        if (end_range > _userFund.end_range) _userFund.end_range = end_range;

        totalScore += score;
        
        Fund_event memory newFund = Fund_event({
            voter: msg.sender,
            voteTime: block.timestamp,
            token: tokenAddress,
            value: amount,
            score: score,
            start_range: st_range,
            end_range: end_range
        });
        funds.push(newFund);
        voteCount++;
    }
        
    /**
    * @notice chain slot auction started. Voters are able to vote to the project.
    */
    function startAuction() external onlyPrimary {
        state = 1; // set the state to 'active' Only primary can do this.
    }
    
    function auctionFailed() external onlyPrimary {
        state = 0; // set the state back to 'passed'
    }
    
    /**
     * @notice Won in the auction. Proceeds to `governane` state and mints governance tokens for contributers.
     */
    function auctionWinned() external onlyPrimary {
      state = 3; // set the state to 'governance'

      uint i;
      for(i = 0; i < finalNumOfVoters; i++) {
        uint256 governs = finalFundByVoter[finalVoters[i]].score * MAG;
        totalGoverns += governs;
        governsByVoter[finalVoters[i]] = governs;
      }
    }

    function blocked(bool blockedType_) external onlyPrimary {
        isBlocked = true;
        blockedType = blockedType_;
    }
    
    /**
     * @notice get fund amount of a voter during the auction.
     * @param voter address to the voter
     * @return score of the given voter
     */
    function getScoreOfVoter(address voter) external view returns(uint256 score) {
      score = fundsByVoter[voter].score;
    }
    
    function finalizeAuction(uint256 _auctionFinishTime) external onlyPrimary returns (uint256) {
        if (_finalized == true) {
            return finalTotalScore;
        }
        uint16 i = 0;
        auctionFinishTime = _auctionFinishTime;
        for (i = 0; i < voteCount; i++) {
            Fund_event storage evt = funds[i];
            if (evt.voteTime > auctionFinishTime) break;
            finalTotalScore += evt.score;
            Fund storage fund = finalFundByVoter[evt.voter];
            if (fund.score == 0) {
                finalVoters.push(evt.voter);
                finalNumOfVoters ++;
            }
            fund.score += evt.score;
            if (fund.amounts[evt.token] == 0) {
                fund.fundTokens.push(evt.token);
            }
            fund.amounts[evt.token] += evt.value;
            if (fund.start_range > evt.start_range) fund.start_range = evt.start_range;
            if (fund.end_range < evt.end_range) fund.end_range = evt.end_range;
        }
        _finalized = true;
        return finalTotalScore;
    }
    
    /**
     * @notice Claim back funds after auction finishes (perhas lose the auction)
     */
    function reFundAll() external {
        require(state == 0, 'Only able to fund on pending state');
        require(isBlocked == false || blockedType == false, 'This project has blocked. You can not reclaim.');
        Fund storage fund = finalFundByVoter[msg.sender];
        require (fund.end_range < block.timestamp, 'Your fund is locked.');
        // BidToken[] = PrimaryInterface(primary).bidTokens();
        // require(fund.amount  > 0, 'No fund for you.');
        // require(cellToken.transferFrom(address(this), msg.sender, fund.amount), 'Insufficient funds');
        uint256 tokenCnt = fund.fundTokens.length;
        require(tokenCnt > 0, 'No fund for you');
        for (uint8 i = 0; i < tokenCnt; i++) {
            address tokenAddress = fund.fundTokens[i];
            uint256 amount = fund.amounts[tokenAddress];
            if (amount > 0) {
                ERC20TokenInterface(tokenAddress).transferFrom(address(this), msg.sender, amount);
            }
        }

        uint256 lastIndex = finalVoters.length - 1;
        uint256 voterIndex = voterIndexes[msg.sender];
        finalVoters[voterIndex] = finalVoters[lastIndex];
        voterIndexes[finalVoters[lastIndex]] = voterIndex;
        finalVoters.pop();
        delete voterIndexes[msg.sender];
        delete finalFundByVoter[msg.sender];
    }
    
    /**
     * @notice refunds the fund that voter votes during the auction but after the auction ends secretly.
     */
    function reFundRemained() external {
        require(isBlocked == false || blockedType == false, 'This project has blocked. You can not reclaim.');
        require(state != 1, 'Unable to refund while auction duration.');
        Fund storage _fund = fundsByVoter[msg.sender];
        Fund storage __fund = finalFundByVoter[msg.sender];
        uint256 tokenCnt = _fund.fundTokens.length;
        require(tokenCnt > 0, 'No fund for you');
        for (uint8 i = 0; i < tokenCnt; i++) {
            address tokenAddress = _fund.fundTokens[i];
            uint256 amount1 = _fund.amounts[tokenAddress];
            uint256 amount2 = __fund.amounts[tokenAddress];
            if (amount1 > amount2) {
                ERC20TokenInterface(tokenAddress).transferFrom(address(this), msg.sender, amount1-amount2);
            }
        }
        // // require(cellToken.transferFrom(address(this), msg.sender, _fund.amount - __fund.amount), 'Insufficient funds');
        // cellToken.transferFrom(address(this), msg.sender, _fund.amount - __fund.amount);
        // _fund.amount = 0;
    }

    function getParticipantInfo() view external returns (uint256 last_score, address bidder, bool isCrowdloan, uint256 st_rng, uint256 end_rng, uint256 totalValue, string memory project_name, address owner, string memory uri, string memory token_name, uint256 totalSupply, uint256 mag) {
        last_score = 0;
        if (voteCount > 0) { 
            Fund_event storage last_bid = funds[voteCount-1];
            last_score = last_bid.value * (last_bid.end_range-last_bid.start_range+1);
            bidder = last_bid.voter;
        }
        st_rng = start_block;
        end_rng = end_block;
        isCrowdloan = participant_type;
        totalValue = totalScore;
        project_name = name;
        owner = manager; 
        uri = metaURI;
        token_name = GT_Name;
        totalSupply = totalGoverns;
        mag = MAG;
    }

    /**
     * @notice Transfer ownership of the project.
     */
    function transferOwnership(address owner) external onlyManager {
        require(owner != address(0), 'The address should not be null.');
        governsByVoter[owner] = governsByVoter[manager];
        delete governsByVoter[manager];
        manager = owner;
    }

    /**
     * @notice Change primary contract address.
     */
    function changePrimary(address primary_) external onlyPrimary {
        require(primary_ != address(0), 'The address should not be null.');
        primary = primary_;
    }

    function withdrawFund(address recipient, address tokenAddress) external onlyPrimary {
        uint256 balance = ERC20TokenInterface(tokenAddress).balanceOf(address(this));
        ERC20TokenInterface(tokenAddress).transfer(recipient, balance);
    }
}
