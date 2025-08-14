// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title WEAVEToken
 * @dev ERC1155 semi-fungible token representing creation rights
 * Soulbound once minted to a user (non-transferable)
 * Supports multiple providers issuing compatible WEAVEs
 */
contract WEAVEToken is ERC1155, AccessControl {
    // Structs
    struct WEAVEData {
        uint256 cronId; // Source CRON that created this
        address creator; // Who spun the CRON
        uint256 createdAt; // Timestamp
        bytes sponsorData; // Carried from CRON metadata
    }

    // Constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    // State variables
    uint256 private _nextTokenId;

    // Mappings
    mapping(uint256 tokenId => WEAVEData data) public weaveData;
    // No need for soulbound mapping - ALL WEAVEs are soulbound

    // Events for ERC5192 Soulbound compliance
    event Locked(uint256 indexed tokenId);
    event Unlocked(uint256 indexed tokenId);
    event WEAVECreated(uint256 indexed tokenId, address indexed creator, uint256 indexed cronId);
    event WEAVEBurned(uint256 indexed tokenId, address indexed from);

    // Custom errors
    error TokenIsSoulbound(uint256 tokenId);
    error WEAVELocked(uint256 tokenId);
    error UnauthorizedTransfer(address from, address to, uint256 tokenId);
    error InsufficientBalance(uint256 tokenId, uint256 required, uint256 available);

    /**
     * @dev Constructor initializes the WEAVE token
     * @param baseUri Base URI for token metadata
     */
    constructor(string memory baseUri) ERC1155(baseUri) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, msg.sender);
    }

    /**
     * @dev Mints a new WEAVE token (always soulbound)
     * @param to Recipient of the WEAVE
     * @param cronId Source CRON NFT ID
     * @param sponsorData Sponsor metadata
     * @param providerId Provider ID for token ID generation
     */
    function mint(
        address to,
        uint256 cronId,
        bytes calldata sponsorData,
        uint16 providerId
    )
        external
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        uint256 tokenId = _generateTokenId(providerId);
        
        // Store metadata
        weaveData[tokenId] = WEAVEData({
            cronId: cronId,
            creator: to,
            createdAt: block.timestamp,
            sponsorData: sponsorData
        });
        
        // Mint token (always 1 per user)
        _mint(to, tokenId, 1, "");
        
        // Emit soulbound lock event for ERC5192 compliance
        emit Locked(tokenId);
        emit WEAVECreated(tokenId, to, cronId);
        
        return tokenId;
    }

    /**
     * @dev Burns a WEAVE token to create a FIBER
     * @param from Address to burn from
     * @param tokenId Token to burn
     */
    function burn(address from, uint256 tokenId) external onlyRole(BURNER_ROLE) {
        uint256 balance = balanceOf(from, tokenId);
        if (balance < 1) {
            revert InsufficientBalance(tokenId, 1, balance);
        }

        _burn(from, tokenId, 1);
        emit WEAVEBurned(tokenId, from);
    }


    /**
     * @dev Checks if a token is locked (always returns true - all WEAVEs are soulbound)
     * @param tokenId Token to check
     */
    function locked(uint256 tokenId) external view returns (bool) {
        return weaveData[tokenId].creator != address(0); // If it exists, it's locked
    }

    /**
     * @dev Sets the URI for all token types
     * @param newuri New URI string
     */
    function setURI(string memory newuri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }

    /**
     * @dev Extracts provider ID from token ID
     * @param tokenId Token ID to decode
     */
    function getProviderId(uint256 tokenId) external pure returns (uint128) {
        return uint128(tokenId >> 128);
    }

    /**
     * @dev Returns the URI for a specific token
     * @param tokenId Token to get URI for
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(super.uri(tokenId), "/", _toString(tokenId)));
    }

    /**
     * @dev Override supportsInterface for AccessControl
     */
    function supportsInterface(bytes4 interfaceId) public view override (ERC1155, AccessControl) returns (bool) {
        // Add ERC5192 interface for Soulbound tokens
        return interfaceId == 0xb45a3c0e || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Override _update to enforce soulbound rules - ALL WEAVEs are soulbound
     */
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    )
        internal
        virtual
        override
    {
        // Only allow minting (from == address(0)) or burning (to == address(0))
        // ALL transfers are blocked
        if (from != address(0) && to != address(0)) {
            revert WEAVELocked(ids[0]);
        }
        
        super._update(from, to, ids, values);
    }

    /**
     * @dev Generates token ID with provider namespace
     * Token ID = (providerId << 240) | uniqueId
     * 16 bits for provider (65,536 possible providers)
     * 240 bits for unique IDs
     */
    function _generateTokenId(uint16 providerId) private returns (uint256) {
        uint256 uniqueId = _nextTokenId;
        ++_nextTokenId;
        return (uint256(providerId) << 240) | uniqueId;
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
