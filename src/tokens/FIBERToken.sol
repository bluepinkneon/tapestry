// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title FIBERToken
 * @dev ERC1155 NFT representing completed comic-style journal entries
 * Each FIBER is unique (amount always = 1) but uses ERC1155 for collection support
 * Supports multiple providers with their own collections
 */
contract FIBERToken is ERC1155, AccessControl {
    // Enums
    enum SponsorType {
        NONE,
        ENTITLEMENT,
        GIFT,
        ADVERTISER,
        VENDOR
    }

    // Structs
    struct FIBERData {
        uint16 providerId; // Which AI created this
        address creator; // Original journal author
        string ipfsHash; // Comic content location
        uint256 dyeUsed; // Computational units consumed
        uint256 costTUSD; // Actual USD cost (6 decimals)
        address sponsor; // If sponsored
        string journalText; // Original input (may be encrypted)
    }

    // Constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    // State variables
    uint256 private _nextTokenId;

    // Mappings
    mapping(uint256 tokenId => FIBERData data) public fiberData;
    mapping(address user => uint256 count) public userFiberCount;
    mapping(uint16 providerId => uint256 count) public providerFiberCount;

    // Events
    event FIBERCreated(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 cost
    );

    // Custom errors
    error ZeroAddress();

    /**
     * @dev Constructor initializes the FIBER token
     * @param baseUri Base URI for token metadata
     */
    constructor(string memory baseUri) ERC1155(baseUri) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, msg.sender);
    }

    /**
     * @dev Mints a new FIBER NFT
     * @param to Recipient of the FIBER
     * @param weaveId Source WEAVE token ID
     * @param ipfsHash IPFS hash of the comic content
     * @param actualCost Actual cost in TUSD (6 decimals)
     */
    function mint(
        address to,
        uint256 weaveId,
        string memory ipfsHash,
        uint256 actualCost
    )
        external
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        if (to == address(0)) revert ZeroAddress();

        uint256 tokenId = _nextTokenId++;
        
        // Store metadata (simplified for now)
        fiberData[tokenId] = FIBERData({
            providerId: 1, // OpenAI hardcoded for now
            creator: to,
            ipfsHash: ipfsHash,
            dyeUsed: 0, // Will be set from WEAVE data
            costTUSD: actualCost,
            sponsor: address(0), // Will be set from WEAVE data
            journalText: "" // Privacy: not stored on-chain
        });
        
        // Mint the FIBER (amount always = 1)
        _mint(to, tokenId, 1, "");
        
        // Update counters
        userFiberCount[to]++;
        providerFiberCount[1]++; // OpenAI

        emit FIBERCreated(tokenId, to, actualCost);
        return tokenId;
    }


    /**
     * @dev Returns statistics for a user
     * @param user Address to query
     */
    function getUserStats(address user) external view returns (uint256 totalFibers, uint256[] memory tokenIds) {
        totalFibers = userFiberCount[user];
        // Note: In production, track user's token IDs more efficiently
        tokenIds = new uint256[](0);
    }

    /**
     * @dev Returns statistics for a provider
     * @param providerId Provider to query
     */
    function getProviderStats(uint16 providerId) external view returns (uint256 totalFibers) {
        return providerFiberCount[providerId];
    }

    /**
     * @dev Sets the base URI for all tokens
     * @param newuri New URI string
     */
    function setURI(string memory newuri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /**
     * @dev Returns the URI for a specific token
     * @param tokenId Token to get URI for
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        FIBERData memory data = fiberData[tokenId];

        // If IPFS hash is set, return it directly
        if (bytes(data.ipfsHash).length > 0) {
            return string(abi.encodePacked("ipfs://", data.ipfsHash));
        }

        // Otherwise return base URI with token ID
        return string(abi.encodePacked(super.uri(tokenId), "/", _toString(tokenId)));
    }

    /**
     * @dev Override supportsInterface for AccessControl
     */
    function supportsInterface(bytes4 interfaceId) public view override (ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Generates token ID with provider and collection namespace
     */
    function _generateTokenId(uint128 providerId, uint128 collectionId) private returns (uint256) {
        uint256 uniqueId = _nextTokenId;
        ++_nextTokenId;
        return (uint256(providerId) << 192) | (uint256(collectionId) << 128) | uniqueId;
    }

    /**
     * @dev Stores metadata for a token
     */
    function _storeMetadata(
        uint256 tokenId,
        address to,
        string calldata ipfsHash,
        FIBERMetadata calldata metadata
    )
        private
    {
        fiberMetadata[tokenId] = FIBERMetadata({
            providerId: metadata.providerId,
            collectionId: metadata.collectionId,
            creator: metadata.creator != address(0) ? metadata.creator : to,
            createdAt: uint64(block.timestamp),
            ipfsHash: ipfsHash,
            dyeUsed: metadata.dyeUsed,
            costTUSD: metadata.costTUSD,
            sponsorType: metadata.sponsorType,
            sponsor: metadata.sponsor,
            journalText: metadata.journalText
        });
    }

    /**
     * @dev Mints token and updates counters
     */
    function _mintAndUpdate(address to, uint256 tokenId, uint128 providerId) private {
        _mint(to, tokenId, 1, "");
        ++userFiberCount[to];
        ++providerFiberCount[providerId];
    }

    /**
     * @dev Helper to convert uint to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            ++digits;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
