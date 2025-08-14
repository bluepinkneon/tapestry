// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { ERC721Enumerable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title CRONToken
 * @dev ERC721 NFT representing a time-wrapped bundle of WEAVE + DYE
 * Each CRON has a 24-hour expiry window and contains creation rights
 */
contract CRONToken is ERC721, ERC721Enumerable, AccessControl {
    // Structs
    struct CRONData {
        uint16 providerId; // Which AI provider (starts with OpenAI = 1)
        uint240 dyeAmount; // Computational units wrapped
        uint256 monetaryValue; // TUSD (subsidy) or hTUSD (premium) amount
        bool isSubsidy; // true = TUSD subsidy, false = hTUSD premium
        address sponsor; // Creator of this CRON
        uint256 expiryTime; // Timestamp + 24 hours
        bytes metadata; // Sponsor branding/requirements
    }

    // Constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    uint256 public constant CRON_DURATION = 24 hours;

    // State variables
    uint256 private _nextTokenId;

    // Mappings
    mapping(uint256 tokenId => CRONData data) public cronData;
    mapping(uint256 tokenId => bool spun) public isSpun;
    mapping(uint256 tokenId => bool expired) public isExpired;

    // Events
    event CRONCreated(
        uint256 indexed tokenId, address indexed recipient, uint16 indexed providerId, uint256 expiryTime
    );
    event CRONSpun(uint256 indexed tokenId, address indexed user, uint240 dyeUsed);
    event CRONExpiredEvent(uint256 indexed tokenId, uint240 dyeReturned);

    // Custom errors
    error CRONAlreadySpun(uint256 tokenId);
    error CRONExpired(uint256 tokenId, uint256 expiryTime);
    error CRONNotExpired(uint256 tokenId, uint256 expiryTime);
    error UnauthorizedCaller(address caller);
    error InvalidExpiryTime();

    /**
     * @dev Constructor initializes the CRON token
     */
    constructor() ERC721("Weave CRON", "CRON") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, msg.sender);
    }

    /**
     * @dev Mints a new CRON NFT
     * @param to Recipient of the CRON
     * @param data CRON metadata and configuration
     */
    function mint(address to, CRONData memory data) external onlyRole(MINTER_ROLE) returns (uint256) {
        if (data.expiryTime <= block.timestamp) revert InvalidExpiryTime();

        uint256 tokenId = _nextTokenId;
        ++_nextTokenId;

        _safeMint(to, tokenId);
        cronData[tokenId] = data;

        emit CRONCreated(tokenId, to, data.providerId, data.expiryTime);

        return tokenId;
    }

    /**
     * @dev Marks a CRON as spun (used)
     * @param tokenId The CRON to mark as spun
     */
    function markSpun(uint256 tokenId) external onlyRole(FACTORY_ROLE) {
        if (isSpun[tokenId]) revert CRONAlreadySpun(tokenId);

        CRONData memory data = cronData[tokenId];
        if (block.timestamp > data.expiryTime) {
            revert CRONExpired(tokenId, data.expiryTime);
        }

        isSpun[tokenId] = true;

        emit CRONSpun(tokenId, ownerOf(tokenId), data.dyeAmount);
    }

    /**
     * @dev Processes an expired CRON, returning resources to pools
     * @param tokenId The expired CRON to process
     */
    function processExpired(uint256 tokenId) external onlyRole(FACTORY_ROLE) {
        CRONData memory data = cronData[tokenId];

        if (block.timestamp <= data.expiryTime) {
            revert CRONNotExpired(tokenId, data.expiryTime);
        }

        if (!isSpun[tokenId] && !isExpired[tokenId]) {
            isExpired[tokenId] = true;
            emit CRONExpiredEvent(tokenId, data.dyeAmount);
        }
    }

    /**
     * @dev Checks if a CRON is expired
     * @param tokenId The CRON to check
     */
    function isTokenExpired(uint256 tokenId) external view returns (bool) {
        return block.timestamp > cronData[tokenId].expiryTime;
    }

    /**
     * @dev Returns the time remaining for a CRON
     * @param tokenId The CRON to check
     */
    function timeRemaining(uint256 tokenId) external view returns (uint256) {
        uint256 expiry = cronData[tokenId].expiryTime;
        if (block.timestamp >= expiry) {
            return 0;
        }
        return expiry - block.timestamp;
    }

    /**
     * @dev Returns full CRON data
     * @param tokenId The CRON to query
     */
    function getCRONData(uint256 tokenId) external view returns (CRONData memory) {
        return cronData[tokenId];
    }

    /**
     * @dev Returns the token URI (could be enhanced with metadata service)
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        // In production, this would return a proper metadata URI
        return string(abi.encodePacked("https://weave.tapestry/cron/", _toString(tokenId)));
    }

    /**
     * @dev Override required by Solidity for ERC721Enumerable
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override (ERC721, ERC721Enumerable)
        returns (address)
    {
        address from = _ownerOf(tokenId);

        // Prevent transfer of spun or expired CRONs
        if (from != address(0)) {
            // Not minting
            if (isSpun[tokenId]) revert CRONAlreadySpun(tokenId);
            if (block.timestamp > cronData[tokenId].expiryTime) {
                revert CRONExpired(tokenId, cronData[tokenId].expiryTime);
            }
        }

        return super._update(to, tokenId, auth);
    }

    /**
     * @dev Override required by Solidity
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override (ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Override required by Solidity for ERC721Enumerable
     */
    function _increaseBalance(address account, uint128 value) internal override (ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
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
