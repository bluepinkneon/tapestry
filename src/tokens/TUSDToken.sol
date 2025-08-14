// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title TUSDToken (Tapestry USD)
 * @dev ERC20 stablecoin pegged 1:1 to USD via company bank account
 * Native stablecoin of Tapestry L2 blockchain
 * Minting/burning controlled by admin to maintain peg with bank reserves
 */
contract TUSDToken is ERC20, AccessControl, Pausable {
    // Constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BLACKLIST_ROLE = keccak256("BLACKLIST_ROLE");

    // State variables
    uint256 public totalMinted;
    uint256 public totalBurned;
    uint256 public bankReserves; // Tracked USD in company bank account

    // Blacklist for compliance
    mapping(address account => bool blocked) public blacklisted;

    // Events
    event Minted(address indexed to, uint256 indexed amount, string indexed reason);
    event Burned(address indexed from, uint256 indexed amount, string indexed reason);
    event BankReservesUpdated(uint256 indexed oldReserves, uint256 indexed newReserves);
    event Blacklisted(address indexed account);
    event Unblacklisted(address indexed account);

    // Custom errors
    error UnauthorizedMinter(address caller);
    error UnauthorizedBurner(address caller);
    error ZeroAmount();
    error BlacklistedAccount(address account);
    error InsufficientReserves(uint256 requested, uint256 available);
    error ReserveMismatch(uint256 supply, uint256 reserves);
    error ContractPaused();

    /**
     * @dev Constructor initializes the TUSD token
     */
    constructor() ERC20("Tapestry USD", "TUSD") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(BLACKLIST_ROLE, msg.sender);
    }

    /**
     * @dev Mints TUSD based on bank reserves
     * @param to Address to receive the tokens
     * @param amount Amount of TUSD to mint (6 decimals)
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (blacklisted[to]) revert BlacklistedAccount(to);
        
        // Check that minting doesn't exceed bank reserves
        uint256 newSupply = totalSupply() + amount;
        if (newSupply > bankReserves) {
            revert InsufficientReserves(newSupply, bankReserves);
        }

        totalMinted += amount;
        _mint(to, amount);

        emit Minted(to, amount, "platform_revenue");
    }

    /**
     * @dev Burns TUSD (admin only for reconciliation)
     * @param amount Amount of TUSD to burn
     */
    function burn(uint256 amount) external onlyRole(BURNER_ROLE) whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        totalBurned += amount;
        _burn(msg.sender, amount);

        emit Burned(msg.sender, amount, "reconciliation");
    }

    /**
     * @dev Updates the tracked bank reserves (for transparency)
     * @param newReserves New reserve amount in USD (6 decimals)
     */
    function updateBankReserves(uint256 newReserves) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldReserves = bankReserves;
        bankReserves = newReserves;

        // Check if reserves match supply (warning only, doesn't revert)
        uint256 supply = totalSupply();
        if (supply != newReserves) {
            // This is a warning condition that should be monitored
            emit BankReservesUpdated(oldReserves, newReserves);
        } else {
            emit BankReservesUpdated(oldReserves, newReserves);
        }
    }

    /**
     * @dev Adds an address to the blacklist
     * @param account Address to blacklist
     */
    function blacklist(address account) external onlyRole(BLACKLIST_ROLE) {
        blacklisted[account] = true;
        emit Blacklisted(account);
    }

    /**
     * @dev Removes an address from the blacklist
     * @param account Address to unblacklist
     */
    function unblacklist(address account) external onlyRole(BLACKLIST_ROLE) {
        blacklisted[account] = false;
        emit Unblacklisted(account);
    }

    /**
     * @dev Pauses all token transfers
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses all token transfers
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Returns the net supply (minted - burned)
     */
    function netSupply() external view returns (uint256) {
        return totalMinted - totalBurned;
    }

    /**
     * @dev Returns reserve ratio (reserves / supply)
     */
    function getReserveRatio() external view returns (uint256 ratio, bool fullyBacked) {
        uint256 supply = totalSupply();
        if (supply == 0) return (1e6, true); // 100% ratio when no supply
        
        ratio = (bankReserves * 1e6) / supply;
        fullyBacked = bankReserves >= supply;
    }

    /**
     * @dev Returns token metrics
     */
    function getMetrics()
        external
        view
        returns (
            uint256 supply,
            uint256 minted,
            uint256 burned,
            uint256 reserves,
            bool fullyBacked
        )
    {
        supply = totalSupply();
        minted = totalMinted;
        burned = totalBurned;
        reserves = bankReserves;
        fullyBacked = bankReserves >= supply;
    }

    /**
     * @dev Override decimals to use 6 (standard for USD stablecoins)
     */
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /**
     * @dev Override supportsInterface for AccessControl
     */
    function supportsInterface(bytes4 interfaceId) public view override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Hook that is called during token transfers
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (!paused()) {
            if (blacklisted[from]) revert BlacklistedAccount(from);
            if (blacklisted[to]) revert BlacklistedAccount(to);
        } else {
            revert ContractPaused();
        }
        super._update(from, to, amount);
    }
}