// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title BucketManager
 * @dev Manages 8 buckets with 6-hour rotation for tracking TUSD/hTUSD/DYE flows
 * Provides 48-hour sliding window analytics and automatic balancing
 */
contract BucketManager is AccessControl {
    // Structs
    struct Bucket {
        uint256 tusdCollected;      // Revenue collected in this period
        uint256 htusdGenerated;     // Deficit created in this period
        uint256 dyeConsumed;        // Computational units used
        uint256 dyeReturned;        // DYE from expired CRONs
        uint256 startTimestamp;     // When this bucket started
        uint256 expiryCount;        // Number of expired CRONs
        uint256 entitlementsClaimed; // Entitlements distributed
        uint256 subsidiesExpired;   // TUSD from expired advertiser CRONs
    }

    // Constants
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");
    uint256 public constant BUCKET_DURATION = 6 hours;
    uint256 public constant NUM_BUCKETS = 8;
    uint256 public constant WINDOW_DURATION = 48 hours; // 8 buckets * 6 hours

    // State variables
    Bucket[8] public buckets;
    uint8 public currentBucketIndex;
    uint256 public lastRotation;
    uint256 public totalBucketsRotated;

    // Events
    event BucketRotated(uint8 indexed newBucket, uint256 timestamp);
    event RevenueRecorded(uint256 amount, uint8 bucket);
    event DeficitRecorded(uint256 amount, uint8 bucket);
    event DYETracked(uint256 consumed, uint256 returned, uint8 bucket);
    event ExpiredSubsidyCollected(uint256 amount, uint8 bucket);

    // Custom errors
    error ZeroAmount();
    error InvalidBucketIndex(uint8 index);

    /**
     * @dev Constructor initializes the bucket system
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FACTORY_ROLE, msg.sender);
        _grantRole(POOL_ROLE, msg.sender);
        
        // Initialize first bucket
        buckets[0].startTimestamp = block.timestamp;
        lastRotation = block.timestamp;
    }

    /**
     * @dev Rotates to next bucket if 6 hours have passed
     */
    function rotateBucketIfNeeded() public {
        if (block.timestamp >= lastRotation + BUCKET_DURATION) {
            _rotateBucket();
        }
    }

    /**
     * @dev Records TUSD revenue in current bucket
     * @param amount Amount of TUSD collected
     */
    function recordRevenue(uint256 amount) external onlyRole(FACTORY_ROLE) {
        if (amount == 0) revert ZeroAmount();
        
        rotateBucketIfNeeded();
        buckets[currentBucketIndex].tusdCollected += amount;
        
        emit RevenueRecorded(amount, currentBucketIndex);
    }

    /**
     * @dev Records hTUSD deficit in current bucket
     * @param amount Amount of hTUSD generated
     */
    function recordDeficit(uint256 amount) external onlyRole(FACTORY_ROLE) {
        if (amount == 0) revert ZeroAmount();
        
        rotateBucketIfNeeded();
        buckets[currentBucketIndex].htusdGenerated += amount;
        
        emit DeficitRecorded(amount, currentBucketIndex);
    }

    /**
     * @dev Records DYE consumption in current bucket
     * @param consumed Amount of DYE consumed
     */
    function recordDYEConsumption(uint256 consumed) external onlyRole(FACTORY_ROLE) {
        if (consumed == 0) revert ZeroAmount();
        
        rotateBucketIfNeeded();
        buckets[currentBucketIndex].dyeConsumed += consumed;
        
        emit DYETracked(consumed, 0, currentBucketIndex);
    }

    /**
     * @dev Records DYE return from expired CRON in current bucket
     * @param returned Amount of DYE returned
     */
    function recordDYEReturn(uint256 returned) external onlyRole(FACTORY_ROLE) {
        if (returned == 0) revert ZeroAmount();
        
        rotateBucketIfNeeded();
        buckets[currentBucketIndex].dyeReturned += returned;
        buckets[currentBucketIndex].expiryCount++;
        
        emit DYETracked(0, returned, currentBucketIndex);
    }

    /**
     * @dev Records expired subsidy collection in current bucket
     * @param amount Amount of TUSD from expired subsidy
     */
    function recordExpiredSubsidy(uint256 amount) external onlyRole(FACTORY_ROLE) {
        if (amount == 0) revert ZeroAmount();
        
        rotateBucketIfNeeded();
        buckets[currentBucketIndex].subsidiesExpired += amount;
        buckets[currentBucketIndex].tusdCollected += amount; // Also counts as revenue
        
        emit ExpiredSubsidyCollected(amount, currentBucketIndex);
    }

    /**
     * @dev Records entitlement claim in current bucket
     */
    function recordEntitlement() external onlyRole(FACTORY_ROLE) {
        rotateBucketIfNeeded();
        buckets[currentBucketIndex].entitlementsClaimed++;
    }

    /**
     * @dev Returns totals for the 48-hour window
     */
    function getWindowTotals() external view returns (
        uint256 totalTUSD,
        uint256 totalHTUSD,
        uint256 totalDYEConsumed,
        uint256 totalDYEReturned,
        uint256 totalExpiries,
        uint256 totalEntitlements
    ) {
        for (uint8 i = 0; i < NUM_BUCKETS; i++) {
            totalTUSD += buckets[i].tusdCollected;
            totalHTUSD += buckets[i].htusdGenerated;
            totalDYEConsumed += buckets[i].dyeConsumed;
            totalDYEReturned += buckets[i].dyeReturned;
            totalExpiries += buckets[i].expiryCount;
            totalEntitlements += buckets[i].entitlementsClaimed;
        }
    }

    /**
     * @dev Returns health metrics based on window data
     */
    function getHealthMetrics() external view returns (
        uint256 revenue48h,
        uint256 deficit48h,
        int256 netPosition,
        uint256 expiryRate,
        uint256 utilizationRate
    ) {
        uint256 totalTUSD;
        uint256 totalHTUSD;
        uint256 totalExpiries;
        uint256 totalEntitlements;
        
        for (uint8 i = 0; i < NUM_BUCKETS; i++) {
            totalTUSD += buckets[i].tusdCollected;
            totalHTUSD += buckets[i].htusdGenerated;
            totalExpiries += buckets[i].expiryCount;
            totalEntitlements += buckets[i].entitlementsClaimed;
        }
        
        revenue48h = totalTUSD;
        deficit48h = totalHTUSD;
        netPosition = int256(totalTUSD) - int256(totalHTUSD);
        
        // Calculate expiry rate (expired / total entitlements)
        if (totalEntitlements > 0) {
            expiryRate = (totalExpiries * 100) / totalEntitlements;
        }
        
        // Calculate utilization (consumed / returned ratio)
        uint256 totalConsumed;
        uint256 totalReturned;
        for (uint8 i = 0; i < NUM_BUCKETS; i++) {
            totalConsumed += buckets[i].dyeConsumed;
            totalReturned += buckets[i].dyeReturned;
        }
        
        if (totalConsumed + totalReturned > 0) {
            utilizationRate = (totalConsumed * 100) / (totalConsumed + totalReturned);
        }
    }

    /**
     * @dev Returns data for a specific bucket
     */
    function getBucket(uint8 index) external view returns (Bucket memory) {
        if (index >= NUM_BUCKETS) revert InvalidBucketIndex(index);
        return buckets[index];
    }

    /**
     * @dev Returns the current bucket data
     */
    function getCurrentBucket() external view returns (Bucket memory) {
        return buckets[currentBucketIndex];
    }

    /**
     * @dev Returns average DYE price over the window
     */
    function getAverageDYEPrice(uint256 totalDYESupply) external view returns (uint256) {
        if (totalDYESupply == 0) return 0;
        
        uint256 totalHTUSD;
        for (uint8 i = 0; i < NUM_BUCKETS; i++) {
            totalHTUSD += buckets[i].htusdGenerated;
        }
        
        return (totalHTUSD * 1e18) / totalDYESupply;
    }

    /**
     * @dev Returns balance recommendation for automatic reconciliation
     */
    function getBalanceRecommendation() external view returns (
        uint256 availableForBurn,
        uint256 excessRevenue
    ) {
        uint256 totalTUSD;
        uint256 totalHTUSD;
        
        for (uint8 i = 0; i < NUM_BUCKETS; i++) {
            totalTUSD += buckets[i].tusdCollected;
            totalHTUSD += buckets[i].htusdGenerated;
        }
        
        if (totalTUSD > totalHTUSD) {
            availableForBurn = totalHTUSD; // Can burn all deficit
            excessRevenue = totalTUSD - totalHTUSD; // Profit for treasury
        } else {
            availableForBurn = totalTUSD; // Can only burn what we have
            excessRevenue = 0;
        }
    }

    /**
     * @dev Internal function to rotate to next bucket
     */
    function _rotateBucket() private {
        uint8 nextBucket = (currentBucketIndex + 1) % uint8(NUM_BUCKETS);
        
        // Clear the bucket we're rotating into (it's 48 hours old)
        delete buckets[nextBucket];
        buckets[nextBucket].startTimestamp = block.timestamp;
        
        currentBucketIndex = nextBucket;
        lastRotation = block.timestamp;
        totalBucketsRotated++;
        
        emit BucketRotated(nextBucket, block.timestamp);
    }

    /**
     * @dev Returns time until next rotation
     */
    function timeUntilRotation() external view returns (uint256) {
        uint256 nextRotation = lastRotation + BUCKET_DURATION;
        if (block.timestamp >= nextRotation) {
            return 0;
        }
        return nextRotation - block.timestamp;
    }

    /**
     * @dev Returns bucket trends (comparing recent vs older buckets)
     */
    function getBucketTrends() external view returns (
        uint256 recentRevenue,
        uint256 olderRevenue,
        uint256 recentDeficit,
        uint256 olderDeficit,
        bool improvingTrend
    ) {
        // Recent = last 4 buckets (24h), Older = previous 4 buckets (24-48h ago)
        for (uint8 i = 0; i < 4; i++) {
            uint8 recentIdx = (currentBucketIndex + NUM_BUCKETS - i) % uint8(NUM_BUCKETS);
            uint8 olderIdx = (currentBucketIndex + NUM_BUCKETS - i - 4) % uint8(NUM_BUCKETS);
            
            recentRevenue += buckets[recentIdx].tusdCollected;
            olderRevenue += buckets[olderIdx].tusdCollected;
            recentDeficit += buckets[recentIdx].htusdGenerated;
            olderDeficit += buckets[olderIdx].htusdGenerated;
        }
        
        // Trend is improving if recent net position is better than older
        int256 recentNet = int256(recentRevenue) - int256(recentDeficit);
        int256 olderNet = int256(olderRevenue) - int256(olderDeficit);
        improvingTrend = recentNet > olderNet;
    }
}