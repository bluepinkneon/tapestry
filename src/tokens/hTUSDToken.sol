// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title hTUSDToken (Tapestry USD Hole)
 * @dev ERC20 token tracking the platform's operational deficit
 * Only mints, never auto-burns
 * Represents total platform costs incurred
 * Admin manually burns during monthly reconciliation
 */
contract hTUSDToken is ERC20, AccessControl {
    // Constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE"); // Only admin can burn for reconciliation

    // State variables
    uint256 public totalDeficit; // Total costs incurred
    uint256 public totalCovered; // Total costs covered by revenue

    // Track costs by category
    mapping(string category => uint256 amount) public costsByCategory;

    // Events
    event DeficitIncurred(uint256 indexed amount, string indexed category);
    event DeficitCovered(uint256 indexed amount, string indexed source);
    event NetPositionChanged(int256 indexed netPosition);

    // Custom errors
    error UnauthorizedMinter(address caller);
    error UnauthorizedBurner(address caller);
    error ZeroAmount();
    error InsufficientDeficit(uint256 requested, uint256 available);

    /**
     * @dev Constructor initializes the hTUSD token
     */
    constructor() ERC20("Tapestry USD Hole", "hTUSD") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev Mints hTUSD when costs are incurred (factory only)
     * @param amount Amount of USD cost (in 6 decimals like TUSD)
     */
    function mint(uint256 amount) external onlyRole(MINTER_ROLE) {
        if (amount == 0) revert ZeroAmount();

        totalDeficit += amount;

        // Mint to treasury
        _mint(msg.sender, amount);

        emit DeficitIncurred(amount, "operational_cost");
    }

    /**
     * @dev Burns hTUSD during monthly reconciliation (admin only)
     * @param amount Amount of deficit to burn
     * @param source Reconciliation note
     */
    function reconcileBurn(uint256 amount, string calldata source) external onlyRole(ADMIN_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (amount > balanceOf(msg.sender)) revert InsufficientDeficit(amount, balanceOf(msg.sender));

        totalCovered += amount;

        // Burn from admin/treasury
        _burn(msg.sender, amount);

        emit DeficitCovered(amount, source);
        emit NetPositionChanged(getNetPosition());
    }

    /**
     * @dev Returns the uncovered deficit
     */
    function getUncoveredDeficit() external view returns (uint256) {
        if (totalDeficit > totalCovered) {
            return totalDeficit - totalCovered;
        }
        return 0;
    }

    /**
     * @dev Returns the net position (negative = deficit, positive = surplus)
     */
    function getNetPosition() public view returns (int256) {
        return int256(totalCovered) - int256(totalDeficit);
    }

    /**
     * @dev Returns platform health metrics
     */
    function getHealthMetrics()
        external
        view
        returns (uint256 deficit, uint256 covered, int256 netPosition, uint256 currentSupply)
    {
        return (totalDeficit, totalCovered, getNetPosition(), totalSupply());
    }

    /**
     * @dev Override decimals to match TUSD (6 decimals)
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}
