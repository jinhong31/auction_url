// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

abstract contract PrimaryInterface {
  function isPrimary() external virtual view returns (bool);
}

contract CellSlots is ERC721Enumerable, Ownable {

  using Strings for uint256;

  string _baseTokenURI;
  mapping (uint256 => uint256) rankOfToken;

  modifier onlyPrimary() {
    PrimaryInterface _pr = PrimaryInterface(msg.sender);
    require(_pr.isPrimary() == true, "Only Primary type contract can do this");
    _;
  }

  constructor() 
    ERC721("Cellframe Network ChainSlot NFT", "CellSlot")  {
    setBaseURI("https://ipfs.io/ipfs/QmUWKwTWyxnWqvHaoWBuNNAzkVBpUBr8DseCLceq4oPf6U/");

  }

  function mint(address slotOwner, uint256 rank) external payable onlyPrimary {

    require(slotOwner != address(0), "Owner address could not be null.");
    // checks if the given slot NFT exists.
    uint256 tokenId = totalSupply() + 1;
    _mint(slotOwner, tokenId);
    rankOfToken[tokenId] = rank;
  }

  function burn(uint256 tokenId) external payable onlyPrimary {
    require(_exists(tokenId) == true, "Slot NFT does not exist");
    _burn(tokenId);
    delete rankOfToken[tokenId];
  }

  function _baseURI() internal view virtual override returns (string memory) {
      return _baseTokenURI;
  }

  function setBaseURI(string memory baseURI) public onlyOwner {
      _baseTokenURI = baseURI;
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    return string(abi.encodePacked(super.tokenURI(tokenId), ".json"));
  }

}
