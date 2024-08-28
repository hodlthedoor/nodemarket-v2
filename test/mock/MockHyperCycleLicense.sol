// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "node_modules/@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Interface for the CHYPC.sol contract.
interface IHyperCycleLicense is IERC721 {
    function mint(uint256 numTokens) external;
    function split(uint256 tokenId) external;
    function burn(uint256 tokenId, string memory burnString) external;
    function merge(uint256 tokenId) external;
    function getBurnData(uint256 tokenId) external view returns (string memory);
    function getLicenseHeight(uint256 licenseId) external view returns (uint8);
    function getLicenseStatus(uint256 licenseId) external view returns (uint256);
}

/// @notice Mock implementation for the IHyperCycleLicense interface.
contract MockHyperCycleLicense is ERC721, IHyperCycleLicense {
    uint256 private _tokenIds;
    mapping(uint256 => string) private _burnData;
    mapping(uint256 => uint8) private _licenseHeight;
    mapping(uint256 => uint256) private _licenseStatus;

    constructor() ERC721("MockHyperCycleLicense", "MHCL") {}

    function mint(uint256 numTokens, address to) public {
        for (uint256 i = 0; i < numTokens; i++) {
            _tokenIds++;
            _mint(to, _tokenIds);
            _licenseHeight[_tokenIds] = 1; // Default height
            _licenseStatus[_tokenIds] = 1; // Default status
        }
    }

    function mint(uint256 numTokens) external  {
        mint(numTokens, _msgSender());
    }

    function split(uint256 tokenId) external {
        require(_exists(tokenId), "Token does not exist");

        // Split logic to create new tokens
        _tokenIds++;
        _mint(ownerOf(tokenId), _tokenIds);
        _licenseHeight[_tokenIds] = _licenseHeight[tokenId] + 1; // Increment height

        _tokenIds++;
        _mint(ownerOf(tokenId), _tokenIds);
        _licenseHeight[_tokenIds] = _licenseHeight[tokenId] + 1; // Increment height
    }

    function burn(uint256 tokenId, string memory burnString) external {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not owner nor approved");
        _burn(tokenId);
        _burnData[tokenId] = burnString;
        _licenseStatus[tokenId] = 0; // Mark as burned
    }

    function merge(uint256 tokenId) external {
        require(_exists(tokenId), "Token does not exist");
        _licenseHeight[tokenId] += 1; // Increase height to indicate merge
    }

    function getBurnData(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        return _burnData[tokenId];
    }

    function getLicenseHeight(uint256 tokenId) external view returns (uint8) {
        require(_exists(tokenId), "Token does not exist");
        return _licenseHeight[tokenId];
    }

    function getLicenseStatus(uint256 tokenId) external view returns (uint256) {
        require(_exists(tokenId), "Token does not exist");
        return _licenseStatus[tokenId];
    }

    // Additional setter methods for testing
    function setBurnData(uint256 tokenId, string memory burnString) external {
        require(_exists(tokenId), "Token does not exist");
        _burnData[tokenId] = burnString;
    }

    function setLicenseHeight(uint256 tokenId, uint8 height) external {
        require(_exists(tokenId), "Token does not exist");
        _licenseHeight[tokenId] = height;
    }

    function setLicenseStatus(uint256 tokenId, uint256 status) external {
        require(_exists(tokenId), "Token does not exist");
        _licenseStatus[tokenId] = status;
    }
}
