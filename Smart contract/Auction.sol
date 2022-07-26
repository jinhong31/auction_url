// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface ERC20TokenInterface {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function balanceOf(address _address) external returns (uint256);
}

contract AuctionContract {
    event ClaimFund(address seller, address winner, uint256 amount);
    event StartAuction(string alert);
    event FinishAuction(string alert);
    event BID(
        uint256 auctionID,
        address bidder,
        uint256 timestamp,
        uint256 amount
    );
    struct bid {
        address bidder;
        uint256 timestamp;
        uint256 amount;
    }

    uint256 public auctionID;
    uint256 public initial_price;
    address public wallet_of_seller;
    string public item_url;
    uint256 public start_date;
    uint256 public end_date;
    uint256 public auction_state;
    address public win_address;
    uint256 public win_amount;
    address public owner;
    bid[] public bids;
    address TBUSD = 0x4614668d17d0FFD422d3edeD7Dd2E8A759Aa4011;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function createAuction(
        uint256 _auctionID,
        uint256 _initial_price,
        address _wallet_of_seller,
        string memory _item_url,
        uint256 _start_date,
        uint256 _end_date
    ) external {
        require(auction_state == 2 || auction_state == 0, "Auction started");
        delete bids;
        auctionID = _auctionID;
        initial_price = _initial_price;
        wallet_of_seller = _wallet_of_seller;
        item_url = _item_url;
        start_date = block.timestamp + _start_date;
        end_date = block.timestamp + _end_date;
        auction_state = 0;
    }

    function createBid(uint256 amount) external {
        require(auction_state == 1, "Auction is not started");
        require(amount > 0, "You should vote at least more than 0");
        bid memory newBid = bid({
            bidder: msg.sender,
            timestamp: block.timestamp,
            amount: amount
        });
        bids.push(newBid);
        emit BID(auctionID, msg.sender, block.timestamp, amount);
    }

    function startAuction() external onlyOwner {
        require(block.timestamp > start_date, "wait");
        auction_state = 1;
        emit StartAuction("Auction started");
    }

    function finishAuction() external onlyOwner {
        require(block.timestamp > end_date, "wait");
        auction_state = 2;
        emit FinishAuction("Auction finished");
        getWinner();
    }

    function getWinner() internal {
        uint256 i;
        win_amount = 0;
        for (i = 0; i < bids.length; i++) {
            if (bids[i].amount > win_amount) {
                win_amount = bids[i].amount;
                win_address = bids[i].bidder;
            }
        }

        require(
            ERC20TokenInterface(TBUSD).balanceOf(win_address) >= win_amount,
            "Insufficient funds"
        );
        claimFund(wallet_of_seller, win_address, win_amount);
    }

    function claimFund(
        address seller,
        address winner,
        uint256 amount
    ) internal onlyOwner {
        ERC20TokenInterface(TBUSD).transferFrom(winner, seller, amount);
        emit ClaimFund(seller, winner, amount);
    }

    function getAllBids() public view returns (bid[] memory) {
        return bids;
    }
}
