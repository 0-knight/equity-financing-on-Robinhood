// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./RepoTypes.sol";

contract RepoToken is ERC721, Ownable {
    uint256 public nextTokenId = 1;

    // tokenId => info
    mapping(uint256 => RepoTypes.RepoTokenInfo) public tokenInfo;

    // tokenId => rehypo repoId (if this RT is used as collateral)
    mapping(uint256 => uint256) public rehypoOf;

    address public servicer; // only RepoServicer can mint/burn

    constructor() ERC721("RepoToken", "RT") Ownable(msg.sender) {}

    function setServicer(address _servicer) external onlyOwner {
        servicer = _servicer;
    }

    modifier onlyServicer() {
        require(msg.sender == servicer, "Only servicer");
        _;
    }

    function mint(
        address to,
        uint256 repoId,
        uint256 principal,
        uint256 repoRate,
        uint256 maturityDate,
        uint256 basketId,
        RepoTypes.CollateralType collateralType,
        uint256 parentTokenId
    ) external onlyServicer returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        _mint(to, tokenId);

        tokenInfo[tokenId] = RepoTypes.RepoTokenInfo({
            repoId: repoId,
            principal: principal,
            repoRate: repoRate,
            maturityDate: maturityDate,
            basketId: basketId,
            collateralType: collateralType,
            parentTokenId: parentTokenId,
            isActive: true
        });
    }

    function burn(uint256 tokenId) external onlyServicer {
        tokenInfo[tokenId].isActive = false;
        _burn(tokenId);
    }

    function setRehypo(uint256 tokenId, uint256 repoId) external onlyServicer {
        rehypoOf[tokenId] = repoId;
    }

    function clearRehypo(uint256 tokenId) external onlyServicer {
        rehypoOf[tokenId] = 0;
    }

    function getRepoTokenInfo(uint256 tokenId) external view returns (RepoTypes.RepoTokenInfo memory) {
        return tokenInfo[tokenId];
    }

    function isRehypoAvailable(uint256 tokenId) external view returns (bool) {
        return tokenInfo[tokenId].isActive && rehypoOf[tokenId] == 0;
    }

    function getCollateralType(uint256 tokenId) external view returns (RepoTypes.CollateralType) {
        return tokenInfo[tokenId].collateralType;
    }
}
