// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockNFT is ERC721, Ownable {
    constructor() Ownable(msg.sender) ERC721("MockNFT", "MNFT") {}

    function mint(address to, uint tokenId) external {
        _mint(to, tokenId);
    }
}
