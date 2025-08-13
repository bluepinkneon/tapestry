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
    struct WEAVEMetadata {
        uint128 providerId; // Which provider issued this
        uint128 cronId; // Source CRON NFT
        uint64 createdAt; // Creation timestamp
        address creator; // Original recipient
        bool locked; // Soulbound flag
        bytes sponsorData; // Sponsor metadata
    }

    // Constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    // State variables
    uint256 private _nextTokenId;

    // Mappings
    mapping(uint256 tokenId => WEAVEMetadata metadata) public weaveMetadata;
    mapping(address user => mapping(uint256 tokenId => bool soulbound)) public soulboundTokens;
    mapping(uint128 providerId => bool active) public activeProviders;

    // Events for ERC5192 Soulbound compliance
    event Locked(uint256 indexed tokenId);
    event Unlocked(uint256 indexed tokenId);
    event WEAVECreated(uint256 indexed tokenId, address indexed creator, uint128 indexed providerId, uint128 cronId);
    event WEAVEBurned(uint256 indexed tokenId, address indexed from, uint256 indexed amount);

    // Custom errors
    error TokenIsSoulbound(uint256 tokenId);
    error InvalidProvider(uint128 providerId);
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
     * @dev Mints a new WEAVE token
     * @param to Recipient of the WEAVE
     * @param providerId Provider issuing this WEAVE
     * @param cronId Source CRON NFT ID
     * @param makeSoulbound Whether to make this token soulbound
     * @param sponsorData Sponsor metadata
     */
    function mint(
        address to,
        uint128 providerId,
        uint128 cronId,
        bool makeSoulbound,
        bytes calldata sponsorData
    )
        external
        onlyRole(MINTER_ROLE)
        returns (uint256)
    {
        if (!activeProviders[providerId] && providerId != 0) {
            revert InvalidProvider(providerId);
        }

        uint256 tokenId = _generateTokenId(providerId);
        _storeMetadata(tokenId, providerId, cronId, to, makeSoulbound, sponsorData);
        _mintToken(to, tokenId, makeSoulbound);

        emit WEAVECreated(tokenId, to, providerId, cronId);
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
        emit WEAVEBurned(tokenId, from, 1);
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
     * @dev Checks if a token is locked (soulbound)
     * @param tokenId Token to check
     */
    function locked(uint256 tokenId) external view returns (bool) {
        return weaveMetadata[tokenId].locked;
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
     * @dev Override _update to enforce soulbound rules
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
        super._update(from, to, ids, values);

        // Skip checks for minting and burning
        if (from == address(0) || to == address(0)) {
            return;
        }

        // Check soulbound status for each token
        _checkSoulboundStatus(from, to, ids);
    }

    /**
     * @dev Generates token ID with provider namespace
     */
    function _generateTokenId(uint128 providerId) private returns (uint256) {
        uint256 uniqueId = _nextTokenId;
        ++_nextTokenId;
        return (uint256(providerId) << 128) | uniqueId;
    }

    /**
     * @dev Stores metadata for a token
     */
    function _storeMetadata(
        uint256 tokenId,
        uint128 providerId,
        uint128 cronId,
        address to,
        bool makeSoulbound,
        bytes calldata sponsorData
    )
        private
    {
        weaveMetadata[tokenId] = WEAVEMetadata({
            providerId: providerId,
            cronId: cronId,
            createdAt: uint64(block.timestamp),
            creator: to,
            locked: makeSoulbound,
            sponsorData: sponsorData
        });
    }

    /**
     * @dev Mints token and handles soulbound logic
     */
    function _mintToken(address to, uint256 tokenId, bool makeSoulbound) private {
        _mint(to, tokenId, 1, "");

        if (makeSoulbound) {
            soulboundTokens[to][tokenId] = true;
            emit Locked(tokenId);
        }
    }

    /**
     * @dev Checks soulbound status during transfers
     */
    function _checkSoulboundStatus(address from, address to, uint256[] memory ids) private view {
        for (uint256 i = 0; i < ids.length; ++i) {
            if (weaveMetadata[ids[i]].locked) {
                revert TokenIsSoulbound(ids[i]);
            }
            if (soulboundTokens[from][ids[i]]) {
                revert UnauthorizedTransfer(from, to, ids[i]);
            }
        }
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
