// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract EscrowNFT is ERC721Burnable, ERC721Enumerable, Ownable {
    uint256 public tokenCounter = 0;

    // NFT data
    mapping(uint256 => uint256) public amount;
    mapping(uint256 => uint256) public matureTime;

    constructor() ERC721("EscrowNFT", "ESCRW") {
    }

    function mint(address _recipient, uint256 _amount, uint256 _matureTime) public onlyOwner returns (uint256) {
        _mint(_recipient, tokenCounter);

        // set values
        amount[tokenCounter] = _amount;
        matureTime[tokenCounter] = _matureTime;

        // increment counter
        tokenCounter++;

        return tokenCounter - 1; // return ID
    }

    function tokenDetails(uint256 _tokenId) public view returns (uint256, uint256) {
        require(_exists(_tokenId), "EscrowNFT: Query for nonexistent token");

        return (amount[_tokenId], matureTime[_tokenId]);
    }

    function contractAddress() public view returns (address) {
        return address(this);
    }

    function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal override(ERC721, ERC721Enumerable) { }

    function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) { }

}

contract Escrow is Ownable {

    EscrowNFT public escrowNFT;
    bool public initialized = false;

    event Escrowed(address _from, address _to, uint256 _amount, uint256 _matureTime);
    event Redeemed(address _recipient, uint256 _amount);
    event Initialized(address _escrowNft);

    modifier isInitialized() {
        require(initialized, "Contract is not yet initialized");
        _;
    }

    function initialize(address _escrowNftAddress) external onlyOwner {
        require(!initialized, "Contract already initialized.");
        escrowNFT = EscrowNFT(_escrowNftAddress);
        initialized = true;

        emit Initialized(_escrowNftAddress);
    }

    function escrowEth(address _recipient, uint256 _duration) external payable isInitialized {
        require(_recipient != address(0), "Cannot escrow to zero address.");
        require(msg.value > 0, "Cannot escrow 0 ETH.");

        uint256 amount = msg.value;
        uint256 matureTime = block.timestamp + _duration;

        escrowNFT.mint(_recipient, amount, matureTime);

        emit Escrowed(msg.sender,
            _recipient,
            amount,
            matureTime);
    }

    function redeemEthFromEscrow(uint256 _tokenId) external isInitialized {
        require(escrowNFT.ownerOf(_tokenId) == msg.sender, "Must own token to claim underlying Eth");

        (uint256 amount, uint256 matureTime) = escrowNFT.tokenDetails(_tokenId);
        require(matureTime <= block.timestamp, "Escrow period not expired.");

        escrowNFT.burn(_tokenId);

        (bool success, ) = msg.sender.call{value: amount}("");

        require(success, "Transfer failed.");

        emit Redeemed(msg.sender, amount);
    }


    function redeemAllAvailableEth() external isInitialized {
        uint256 nftBalance = escrowNFT.balanceOf(msg.sender);
        require(nftBalance > 0, "No EscrowNFTs to redeem.");

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < nftBalance; i++) {
            uint256 tokenId = escrowNFT.tokenOfOwnerByIndex(msg.sender, i);
            (uint256 amount, uint256 matureTime) = escrowNFT.tokenDetails(tokenId);

            if (matureTime <= block.timestamp) {
                escrowNFT.burn(tokenId);
                totalAmount += amount;
            }
        }

        require(totalAmount > 0, "No Ether to redeem.");

        (bool success, ) = msg.sender.call{value: totalAmount}("");

        require(success, "Transfer failed.");

        emit Redeemed(msg.sender, totalAmount);
    }

    function contractAddress() public view returns (address) {
        return address(this);
    }

}