// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title DYEToken
 * @dev ERC20 token representing computational units in the Weave ecosystem
 * DYE is consumed when creating FIBERs and tracks computational costs
 */
contract DYEToken is ERC20, AccessControl {
    // Constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // State variables
    uint256 public totalMinted;
    uint256 public totalBurned;

    // Events
    event DyeMinted(address indexed to, uint256 indexed amount);
    event DyeBurned(address indexed from, uint256 indexed amount);

    // Custom errors
    error UnauthorizedMinter(address caller);
    error UnauthorizedBurner(address caller);
    error ZeroAmount();

    /**
     * @dev Constructor initializes the DYE token
     */
    constructor() ERC20("Weave DYE", "DYE") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
    }

    /**
     * @dev Mints new DYE tokens
     * @param to Address to receive the tokens
     * @param amount Amount of DYE to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        if (amount == 0) revert ZeroAmount();

        totalMinted += amount;
        _mint(to, amount);

        emit DyeMinted(to, amount);
    }

    /**
     * @dev Burns DYE tokens from a specific address
     * @param from Address to burn tokens from
     * @param amount Amount of DYE to burn
     */
    function burnFrom(address from, uint256 amount) external onlyRole(BURNER_ROLE) {
        if (amount == 0) revert ZeroAmount();

        totalBurned += amount;
        _burn(from, amount);

        emit DyeBurned(from, amount);
    }

    /**
     * @dev Returns the net supply (minted - burned)
     */
    function netSupply() external view returns (uint256) {
        return totalMinted - totalBurned;
    }

    /**
     * @dev Returns token metrics
     */
    function getMetrics() external view returns (uint256 supply, uint256 minted, uint256 burned) {
        return (totalSupply(), totalMinted, totalBurned);
    }
}
