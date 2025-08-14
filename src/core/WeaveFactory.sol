// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { BucketManager } from "./BucketManager.sol";
import { CRONToken } from "../tokens/CRONToken.sol";
import { WEAVEToken } from "../tokens/WEAVEToken.sol";
import { FIBERToken } from "../tokens/FIBERToken.sol";
import { DYEToken } from "../tokens/DYEToken.sol";
import { TUSDToken } from "../tokens/TUSDToken.sol";
import { hTUSDToken } from "../tokens/hTUSDToken.sol";

/**
 * @title WeaveFactory
 * @dev Main orchestrator for the Weave ecosystem
 * Manages CRON creation, spinning, expiry, and FIBER completion
 * Integrates with BucketManager for automatic TUSD/hTUSD balancing
 */
contract WeaveFactory is AccessControl {
    // State variables - Token contracts
    CRONToken public immutable cronToken;
    WEAVEToken public immutable weaveToken;
    FIBERToken public immutable fiberToken;
    DYEToken public immutable dyeToken;
    TUSDToken public immutable tusdToken;
    hTUSDToken public immutable htusdToken;
    
    // State variables - Core contracts
    BucketManager public immutable bucketManager;
    address public pool;
    address public treasury;
    address public entitlementManager;
    
    // Constants
    bytes32 public constant BACKEND_ROLE = keccak256("BACKEND_ROLE");
    bytes32 public constant ENTITLEMENT_ROLE = keccak256("ENTITLEMENT_ROLE");
    uint256 public constant INITIAL_DYE_PRICE = 0.05e6; // $0.05 in TUSD decimals
    uint256 public constant BASE_DYE_AMOUNT = 1000; // Base DYE units per operation
    
    // Tracking
    mapping(uint256 weaveId => uint256 cronId) public weaveToCron;
    mapping(uint256 cronId => bool processed) public expiredCronProcessed;
    
    // Events
    event CRONCreated(uint256 indexed cronId, address indexed recipient, uint256 expiryTime);
    event CRONSpun(uint256 indexed cronId, uint256 indexed weaveId, address indexed user);
    event CRONExpired(uint256 indexed cronId, uint256 weaveReturned, uint256 dyeReturned);
    event WEAVECompleted(uint256 indexed weaveId, uint256 indexed fiberId, uint256 actualCost);
    event SubsidyExpired(uint256 indexed cronId, uint256 amount);
    
    // Custom errors
    error Unauthorized();
    error CRONNotOwned();
    error CRONExpired();
    error CRONNotExpired();
    error AlreadyProcessed();
    error InvalidAmount();
    error PoolNotSet();
    
    constructor(
        address _cronToken,
        address _weaveToken,
        address _fiberToken,
        address _dyeToken,
        address _tusdToken,
        address _htusdToken,
        address _bucketManager
    ) {
        cronToken = CRONToken(_cronToken);
        weaveToken = WEAVEToken(_weaveToken);
        fiberToken = FIBERToken(_fiberToken);
        dyeToken = DYEToken(_dyeToken);
        tusdToken = TUSDToken(_tusdToken);
        htusdToken = hTUSDToken(_htusdToken);
        bucketManager = BucketManager(_bucketManager);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    /**
     * @dev Creates an entitlement CRON (platform subsidized)
     * @param recipient Address to receive the CRON
     */
    function createEntitlementCRON(address recipient) external onlyRole(ENTITLEMENT_ROLE) {
        // Mint DYE for the operation
        dyeToken.mint(address(this), BASE_DYE_AMOUNT);
        
        // Calculate and mint hTUSD for deficit tracking
        uint256 dyePrice = _getDYEPrice();
        uint256 htusdAmount = (BASE_DYE_AMOUNT * dyePrice) / 1e18;
        htusdToken.mint(htusdAmount);
        
        // Record in buckets
        bucketManager.recordDYEConsumption(BASE_DYE_AMOUNT);
        bucketManager.recordDeficit(htusdAmount);
        bucketManager.recordEntitlement();
        
        // Create CRON data
        CRONToken.CRONData memory data = CRONToken.CRONData({
            providerId: 1, // OpenAI
            dyeAmount: BASE_DYE_AMOUNT,
            monetaryValue: 0, // No monetary value for entitlements
            isSubsidy: false,
            sponsor: address(0),
            expiryTime: block.timestamp + 24 hours,
            metadata: ""
        });
        
        // Mint CRON
        uint256 cronId = cronToken.mint(recipient, data);
        emit CRONCreated(cronId, recipient, data.expiryTime);
    }
    
    /**
     * @dev Creates an advertiser CRON with TUSD subsidy
     * @param recipient Target user for the CRON
     * @param tusdSubsidy Amount of TUSD subsidy
     * @param distributionFee Fee paid by advertiser
     * @param metadata Advertiser branding/requirements
     */
    function createAdvertiserCRON(
        address recipient,
        uint256 tusdSubsidy,
        uint256 distributionFee,
        bytes calldata metadata
    ) external {
        if (tusdSubsidy == 0) revert InvalidAmount();
        
        // Collect distribution fee + subsidy from advertiser
        tusdToken.transferFrom(msg.sender, address(this), tusdSubsidy + distributionFee);
        
        // Record distribution fee as revenue
        if (distributionFee > 0) {
            bucketManager.recordRevenue(distributionFee);
            tusdToken.transfer(treasury, distributionFee);
        }
        
        // Mint DYE
        dyeToken.mint(address(this), BASE_DYE_AMOUNT);
        
        // Track costs
        uint256 dyePrice = _getDYEPrice();
        uint256 htusdAmount = (BASE_DYE_AMOUNT * dyePrice) / 1e18;
        htusdToken.mint(htusdAmount);
        
        bucketManager.recordDYEConsumption(BASE_DYE_AMOUNT);
        bucketManager.recordDeficit(htusdAmount);
        
        // Create CRON with subsidy
        CRONToken.CRONData memory data = CRONToken.CRONData({
            providerId: 1,
            dyeAmount: BASE_DYE_AMOUNT,
            monetaryValue: tusdSubsidy,
            isSubsidy: true,
            sponsor: msg.sender,
            expiryTime: block.timestamp + 24 hours,
            metadata: metadata
        });
        
        uint256 cronId = cronToken.mint(recipient, data);
        emit CRONCreated(cronId, recipient, data.expiryTime);
    }
    
    /**
     * @dev Spins a CRON to create a soulbound WEAVE
     * @param cronId CRON token to spin
     */
    function spinCRON(uint256 cronId) external {
        // Verify ownership and not expired
        if (cronToken.ownerOf(cronId) != msg.sender) revert CRONNotOwned();
        
        CRONToken.CRONData memory data = cronToken.cronData(cronId);
        if (block.timestamp > data.expiryTime) revert CRONExpired();
        
        // Mark as spun
        cronToken.markSpun(cronId);
        
        // Burn DYE
        dyeToken.burn(data.dyeAmount);
        
        // Create soulbound WEAVE
        uint256 weaveId = weaveToken.mint(
            msg.sender,
            cronId,
            data.metadata,
            data.providerId
        );
        
        weaveToCron[weaveId] = cronId;
        
        // Handle monetary value
        if (data.monetaryValue > 0) {
            if (data.isSubsidy) {
                // User receives TUSD subsidy
                tusdToken.transfer(msg.sender, data.monetaryValue);
            } else {
                // User pays hTUSD premium to vendor
                htusdToken.transferFrom(msg.sender, data.sponsor, data.monetaryValue);
            }
        }
        
        // Trigger compaction for any expired CRONs
        _performCompaction();
        
        emit CRONSpun(cronId, weaveId, msg.sender);
    }
    
    /**
     * @dev Backend completes WEAVE processing to create FIBER
     * @param weaveId WEAVE token to process
     * @param success Whether processing succeeded
     * @param actualCostTUSD Actual cost in TUSD (6 decimals)
     * @param ipfsHash IPFS hash of the comic content
     */
    function completeWEAVE(
        uint256 weaveId,
        bool success,
        uint256 actualCostTUSD,
        string memory ipfsHash
    ) external onlyRole(BACKEND_ROLE) {
        address creator = weaveToken.weaveData(weaveId).creator;
        
        if (success) {
            // Burn WEAVE
            weaveToken.burn(creator, weaveId);
            
            // Mint FIBER
            uint256 fiberId = fiberToken.mint(creator, weaveId, ipfsHash, actualCostTUSD);
            
            // Track actual cost as deficit
            htusdToken.mint(actualCostTUSD);
            bucketManager.recordDeficit(actualCostTUSD);
            
            emit WEAVECompleted(weaveId, fiberId, actualCostTUSD);
        } else {
            // Even on failure, track the cost
            if (actualCostTUSD > 0) {
                htusdToken.mint(actualCostTUSD);
                bucketManager.recordDeficit(actualCostTUSD);
            }
        }
        
        // Trigger compaction
        _performCompaction();
    }
    
    /**
     * @dev Performs compaction - processes expired CRONs
     */
    function _performCompaction() private {
        // Process up to 10 expired CRONs per call to limit gas
        uint256 totalSupply = cronToken.totalSupply();
        uint256 processed = 0;
        
        for (uint256 i = 0; i < totalSupply && processed < 10; i++) {
            uint256 cronId = cronToken.tokenByIndex(i);
            
            if (!expiredCronProcessed[cronId] && !cronToken.isSpun(cronId)) {
                CRONToken.CRONData memory data = cronToken.cronData(cronId);
                
                if (block.timestamp > data.expiryTime) {
                    _processExpiredCRON(cronId, data);
                    expiredCronProcessed[cronId] = true;
                    processed++;
                }
            }
        }
    }
    
    /**
     * @dev Processes a single expired CRON
     */
    function _processExpiredCRON(uint256 cronId, CRONToken.CRONData memory data) private {
        // Return WEAVE to pool (if pool is set)
        if (pool != address(0)) {
            // Pool will handle WEAVE increment
        }
        
        // Return DYE to circulation
        bucketManager.recordDYEReturn(data.dyeAmount);
        
        // Handle expired monetary value with automatic balancing
        if (data.monetaryValue > 0 && data.isSubsidy) {
            // Expired advertiser subsidy - use for automatic balancing
            bucketManager.recordExpiredSubsidy(data.monetaryValue);
            
            // Burn hTUSD with the expired subsidy
            uint256 burnAmount = _min(data.monetaryValue, htusdToken.totalSupply());
            if (burnAmount > 0) {
                htusdToken.reconcileBurn(burnAmount, "auto_balance_expired_subsidy");
            }
            
            // Excess goes to treasury
            if (data.monetaryValue > burnAmount) {
                tusdToken.transfer(treasury, data.monetaryValue - burnAmount);
            }
            
            emit SubsidyExpired(cronId, data.monetaryValue);
        }
        
        emit CRONExpired(cronId, 1, data.dyeAmount);
    }
    
    /**
     * @dev Calculates current DYE price based on bucket window
     */
    function _getDYEPrice() private view returns (uint256) {
        uint256 dyeSupply = dyeToken.totalSupply();
        if (dyeSupply == 0) return INITIAL_DYE_PRICE;
        
        return bucketManager.getAverageDYEPrice(dyeSupply);
    }
    
    /**
     * @dev Helper function for min
     */
    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
    
    /**
     * @dev Sets the pool address
     */
    function setPool(address _pool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pool = _pool;
    }
    
    /**
     * @dev Sets the treasury address
     */
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasury = _treasury;
    }
    
    /**
     * @dev Sets the entitlement manager address
     */
    function setEntitlementManager(address _entitlementManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        entitlementManager = _entitlementManager;
        _grantRole(ENTITLEMENT_ROLE, _entitlementManager);
    }
}