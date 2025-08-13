// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title hTUSDToken (Tapestry USD Hole)
 * @dev ERC20 token tracking the platform's deficit/costs
 * Minted when FIBERs are created (representing actual USD costs)
 * Burned when revenue is received (reducing deficit)
 */
contract hTUSDToken is ERC20, AccessControl {
    // Constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

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
        _grantRole(BURNER_ROLE, msg.sender);
    }

    /**
     * @dev Mints hTUSD when costs are incurred
     * @param amount Amount of USD cost (in 6 decimals like TUSD)
     * @param category Cost category for tracking
     */
    function mintDeficit(uint256 amount, string calldata category) external onlyRole(MINTER_ROLE) {
        if (amount == 0) revert ZeroAmount();

        totalDeficit += amount;
        costsByCategory[category] += amount;

        // Mint to treasury or designated holder
        _mint(msg.sender, amount);

        emit DeficitIncurred(amount, category);
        emit NetPositionChanged(getNetPosition());
    }

    /**
     * @dev Burns hTUSD when revenue covers costs
     * @param amount Amount of deficit to cover
     * @param source Revenue source (e.g., "distribution_fee", "advertiser_subsidy")
     */
    function burnDeficit(uint256 amount, string calldata source) external onlyRole(BURNER_ROLE) {
        if (amount == 0) revert ZeroAmount();
        if (amount > totalSupply()) revert InsufficientDeficit(amount, totalSupply());

        totalCovered += amount;

        // Burn from treasury or designated holder
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
