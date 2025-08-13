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
    struct FIBERMetadata {
        uint128 providerId; // Which provider created this
        uint128 collectionId; // Provider's collection
        address creator; // User who created this
        uint64 createdAt; // Creation timestamp
        string ipfsHash; // Comic content on IPFS
        uint128 dyeUsed; // Computational units consumed
        uint64 costUSDC; // Actual USD cost (6 decimals)
        SponsorType sponsorType; // Type of sponsorship
        address sponsor; // Sponsor address (if any)
        string journalText; // Original journal entry
    }

    // Constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    // State variables
    uint256 private _nextTokenId;

    // Mappings
    mapping(uint256 tokenId => FIBERMetadata metadata) public fiberMetadata;
    mapping(uint128 providerId => mapping(uint128 collectionId => string name)) public collectionNames;
    mapping(uint128 providerId => bool active) public activeProviders;
    mapping(address user => uint256 count) public userFiberCount;
    mapping(uint128 providerId => uint256 count) public providerFiberCount;

    // Events
    event FIBERCreated(
        uint256 indexed tokenId,
        address indexed creator,
        uint128 indexed providerId,
        uint128 collectionId,
        string ipfsHash
    );
    event CollectionCreated(uint128 indexed providerId, uint128 indexed collectionId, string name);

    // Custom errors
    error InvalidProvider(uint128 providerId);
    error InvalidCollection(uint128 providerId, uint128 collectionId);
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
     * @param providerId Provider who created this
     * @param collectionId Collection within the provider
     * @param ipfsHash IPFS hash of the comic content
     * @param metadata Additional metadata
     */
    function mint(
        address to,
        uint128 providerId,
        uint128 collectionId,
        string calldata ipfsHash,
        FIBERMetadata calldata metadata
    )
        external
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        if (to == address(0)) revert ZeroAddress();
        if (!activeProviders[providerId] && providerId != 0) {
            revert InvalidProvider(providerId);
        }

        uint256 tokenId = _generateTokenId(providerId, collectionId);
        _storeMetadata(tokenId, to, ipfsHash, metadata);
        _mintAndUpdate(to, tokenId, providerId);

        emit FIBERCreated(tokenId, to, providerId, collectionId, ipfsHash);
        return tokenId;
    }

    /**
     * @dev Creates a new collection for a provider
     * @param providerId Provider ID
     * @param collectionId Collection ID
     * @param name Collection name
     */
    function createCollection(
        uint128 providerId,
        uint128 collectionId,
        string calldata name
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        collectionNames[providerId][collectionId] = name;
        emit CollectionCreated(providerId, collectionId, name);
    }

    /**
     * @dev Activates a provider
     * @param providerId Provider to activate
     */
    function activateProvider(uint128 providerId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        activeProviders[providerId] = true;
    }

    /**
     * @dev Deactivates a provider
     * @param providerId Provider to deactivate
     */
    function deactivateProvider(uint128 providerId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        activeProviders[providerId] = false;
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
     * @dev Extracts provider ID from token ID
     * @param tokenId Token ID to decode
     */
    function getProviderId(uint256 tokenId) external pure returns (uint128) {
        return uint128(tokenId >> 192);
    }

    /**
     * @dev Extracts collection ID from token ID
     * @param tokenId Token ID to decode
     */
    function getCollectionId(uint256 tokenId) external pure returns (uint128) {
        return uint128((tokenId >> 128) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
    }

    /**
     * @dev Returns statistics for a provider
     * @param providerId Provider to query
     */
    function getProviderStats(uint128 providerId) external view returns (bool isActive, uint256 totalFibers) {
        return (activeProviders[providerId], providerFiberCount[providerId]);
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
        FIBERMetadata memory metadata = fiberMetadata[tokenId];

        // If IPFS hash is set, return it directly
        if (bytes(metadata.ipfsHash).length > 0) {
            return string(abi.encodePacked("ipfs://", metadata.ipfsHash));
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
            costUSDC: metadata.costUSDC,
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
