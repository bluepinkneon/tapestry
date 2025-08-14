# Technical Design Document: Weave Ecosystem

**Version**: 2.0  
**Date**: August 13, 2025  
**Status**: Implementation Ready

## Executive Summary

The Weave ecosystem transforms personal journal entries into comic-style NFTs on Tapestry L2 blockchain. The protocol uses a dual-token economic model to track computational costs (DYE) and platform deficit (hTUSD), while providing users with time-based entitlements and enabling advertiser/vendor participation through wrapped time-sensitive bundles (CRONs).

## 1. System Overview

### 1.1 Core Concept
Users receive free CRON tokens every 6 hours containing creation rights (WEAVE) and computational units (DYE). These CRONs expire in 24 hours, creating natural scarcity. Users "spin" CRONs to create soulbound WEAVEs, which are then processed by AI into FIBER NFTs (comic panels).

### 1.2 Economic Innovation
- **Expired Inventory Monetization**: Expired CRONs return WEAVE to a pool, creating a secondary market
- **Deficit Tracking**: hTUSD mints track platform costs; TUSD mints track revenue
- **Self-Balancing**: DYE price = hTUSD supply / DYE supply (actual cost basis)
- **No Auto-Burns**: Revenue accumulates as TUSD; monthly reconciliation by admin

### 1.3 Key Actors
1. **Users**: Claim entitlements, spin CRONs, own FIBERs
2. **Platform**: Provides infrastructure, manages deficit
3. **Advertisers**: Subsidize CRONs for branded content
4. **Vendors**: Create premium CRONs for enhanced features
5. **Pool Traders**: Buy WEAVE directly with TUSD

## 2. Token Specifications

### 2.1 CRON Token (ERC-721)
Time-wrapped bundles with 24-hour expiry.

```solidity
struct CRONData {
    uint16 providerId;        // Which AI provider (starts with OpenAI = 1)
    uint240 dyeAmount;        // Computational units wrapped
    uint256 monetaryValue;    // TUSD (subsidy) or hTUSD (premium) amount
    bool isSubsidy;          // true = TUSD subsidy, false = hTUSD premium
    address sponsor;         // Creator of this CRON
    uint256 expiryTime;      // Timestamp + 24 hours
    bytes metadata;          // Sponsor branding/requirements
}
```

**Three Types of CRONs**:
1. **Platform/Entitlement**: WEAVE + DYE only (no fees, no monetary value)
2. **Advertiser**: WEAVE + DYE + TUSD subsidy + distribution fee
3. **Vendor**: WEAVE + DYE + hTUSD premium + distribution fee

### 2.2 WEAVE Token (ERC-1155)
Soulbound creation rights. ALWAYS non-transferable.

```solidity
// Token ID structure: (providerId << 240) | uniqueId
// 16 bits for provider (65,536 possible providers)
// 240 bits for unique IDs

struct WEAVEData {
    uint256 cronId;          // Source CRON that created this
    address creator;         // Who spun the CRON
    uint256 createdAt;       // Timestamp
    bytes sponsorData;       // Carried from CRON metadata
}
```

### 2.3 FIBER Token (ERC-1155)
Final comic NFT output. Transferable and tradeable.

```solidity
struct FIBERData {
    uint16 providerId;       // Which AI created this
    address creator;         // Original journal author
    string ipfsHash;         // Comic content location
    uint256 dyeUsed;         // Computational units consumed
    uint256 costTUSD;        // Actual USD cost (6 decimals)
    address sponsor;         // If sponsored
    string journalText;      // Original input (may be encrypted)
}
```

### 2.4 DYE Token (ERC-20)
Computational units. Minted when creating CRONs, burned when spinning.

```solidity
contract DYEToken is ERC20 {
    // Price = totalSupply(hTUSD) / totalSupply(DYE)
    // Reflects actual computational cost basis
}
```

### 2.5 TUSD Token (ERC-20)
Tapestry USD - Native L2 stablecoin, 1:1 with company bank account.

```solidity
contract TUSDToken is ERC20, Pausable {
    uint256 public bankReserves;  // Tracked USD in bank
    mapping(address => bool) public blacklisted;
    
    // Admin controlled minting based on bank deposits
    function mint(address to, uint256 amount) external onlyAdmin {
        require(amount <= bankReserves - totalSupply(), "Exceeds reserves");
        _mint(to, amount);
    }
}
```

### 2.6 hTUSD Token (ERC-20)
"Hole" TUSD - Tracks platform's operational deficit.

```solidity
contract hTUSDToken is ERC20 {
    // Only mints, never auto-burns
    // Represents total platform costs incurred
    
    function mint(uint256 amount) external onlyFactory {
        _mint(treasury, amount);
    }
}
```

## 3. Core Contracts

### 3.1 WeaveFactory
Main orchestrator for the ecosystem.

```solidity
contract WeaveFactory {
    // Token references
    CRONToken public cronToken;
    WEAVEToken public weaveToken;
    FIBERToken public fiberToken;
    DYEToken public dyeToken;
    hTUSDToken public htusdToken;
    TUSDToken public tusdToken;
    
    // Configuration
    uint256 public constant CRON_DURATION = 24 hours;
    uint256 public constant INITIAL_DYE_PRICE = 0.05e6; // $0.05 in TUSD decimals
    
    // Core functions
    function createEntitlementCRON(address recipient) external;
    function createAdvertiserCRON(
        address recipient, 
        uint256 tusdSubsidy,
        uint256 distributionFee,
        bytes calldata metadata
    ) external;
    function createVendorCRON(
        address recipient,
        uint256 htusdPremium,
        uint256 distributionFee,
        bytes calldata metadata
    ) external;
    function spinCRON(uint256 cronId) external;
    function completeWEAVE(
        uint256 weaveId,
        bool success,
        uint256 actualCostTUSD,
        string memory ipfsHash
    ) external onlyBackend;
}
```

### 3.2 EntitlementManager
Manages 6-hour entitlement distributions.

```solidity
contract EntitlementManager {
    uint256 public constant ENTITLEMENT_INTERVAL = 6 hours;
    
    mapping(address => uint256) public lastClaim;
    
    function claimEntitlement() external {
        // Relative timing - smooth, no cliffs
        require(block.timestamp >= lastClaim[msg.sender] + ENTITLEMENT_INTERVAL, "Too soon");
        
        lastClaim[msg.sender] = block.timestamp;
        factory.createEntitlementCRON(msg.sender);
    }
}
```

### 3.3 ProviderRegistry
Minimal registry for AI provider management.

```solidity
contract ProviderRegistry {
    struct Provider {
        string name;
        address operator;
        uint256 baseDyeAmount;    // Standard operation cost
        bool active;
    }
    
    mapping(uint16 => Provider) public providers;
    uint16 public providerCount;
    
    constructor() {
        // Bootstrap with OpenAI
        providers[1] = Provider({
            name: "OpenAI",
            operator: address(0), // Will be set to backend
            baseDyeAmount: 1000,  // Base DYE units
            active: true
        });
        providerCount = 1;
    }
}
```

### 3.4 SimpleCRONPool
AMM for WEAVE <-> TUSD trading.

```solidity
contract SimpleCRONPool {
    uint256 public weaveReserve;
    uint256 public tusdReserve;
    bool public poolOpen;
    
    // Pool starts closed, opens after sufficient inventory
    modifier whenOpen() {
        require(poolOpen, "Pool not yet open");
        _;
    }
    
    function openPool() external onlyAdmin {
        require(weaveReserve >= MIN_WEAVE_LIQUIDITY, "Insufficient WEAVE");
        poolOpen = true;
    }
    
    function getPrice() public view returns (uint256) {
        if (weaveReserve == 0) return getDYEPrice();
        return (tusdReserve * 1e18) / weaveReserve;
    }
    
    function getDYEPrice() public view returns (uint256) {
        uint256 htusdSupply = htusdToken.totalSupply();
        uint256 dyeSupply = dyeToken.totalSupply();
        
        if (dyeSupply == 0) return INITIAL_DYE_PRICE;
        return (htusdSupply * 1e18) / dyeSupply;
    }
    
    function maintainPriceFloor() external {
        uint256 dyePrice = getDYEPrice();
        uint256 poolPrice = getPrice();
        
        if (poolPrice < dyePrice) {
            // Price below floor - intervention needed
            uint256 deficit = (weaveReserve * dyePrice) - tusdReserve;
            
            // Mint hTUSD to track intervention cost
            htusdToken.mint(deficit);
            
            // Burn equivalent DYE to reduce supply
            uint256 dyeToBurn = (deficit * 1e18) / dyePrice;
            dyeToken.burn(dyeToBurn);
            
            // Add TUSD to pool to restore floor
            tusdReserve += deficit;
        }
    }
}
```

### 3.5 BucketManager
Manages 8 buckets with 6-hour rotation for automatic TUSD/hTUSD balancing.

```solidity
contract BucketManager {
    struct Bucket {
        uint256 tusdCollected;      // Revenue in this 6h period
        uint256 htusdGenerated;     // Deficit in this 6h period
        uint256 dyeConsumed;        // DYE used for operations
        uint256 dyeReturned;        // DYE from expired CRONs
        uint256 startTimestamp;     // Bucket start time
        uint256 expiryCount;        // Expired CRONs processed
        uint256 entitlementsClaimed; // Entitlements in period
        uint256 subsidiesExpired;   // TUSD from expired advertiser CRONs
    }
    
    Bucket[8] public buckets;
    uint8 public currentBucketIndex;
    uint256 public constant BUCKET_DURATION = 6 hours;
    
    // Automatic rotation every 6 hours
    function rotateBucketIfNeeded() public {
        if (block.timestamp >= lastRotation + BUCKET_DURATION) {
            currentBucketIndex = (currentBucketIndex + 1) % 8;
            delete buckets[currentBucketIndex]; // Clear 48h old data
            buckets[currentBucketIndex].startTimestamp = block.timestamp;
        }
    }
    
    // 48-hour sliding window analytics
    function getWindowTotals() external view returns (
        uint256 totalTUSD,
        uint256 totalHTUSD,
        uint256 totalDYEConsumed,
        uint256 totalDYEReturned
    );
    
    // Automatic balancing during compaction
    // Expired subsidies automatically burn hTUSD deficit
}
```

### 3.6 Treasury
Manages platform funds with manual admin control.

```solidity
contract Treasury {
    TUSDToken public tusdToken;
    hTUSDToken public htusdToken;
    
    // Revenue sources mint TUSD here
    function recordRevenue(uint256 amount) external onlyFactory {
        tusdToken.mint(address(this), amount);
    }
    
    // Admin manually reconciles monthly
    function reconcileBooks(uint256 burnAmount) external onlyAdmin {
        // CFO/Admin decides how much hTUSD to burn based on books
        require(tusdToken.balanceOf(address(this)) >= burnAmount, "Insufficient TUSD");
        
        tusdToken.burn(burnAmount);
        htusdToken.burn(burnAmount);
        
        emit MonthlyReconciliation(burnAmount, block.timestamp);
    }
}
```

## 4. Economic Flows

### 4.1 Entitlement Flow
```
1. User calls claimEntitlement() after 6 hours
2. Platform creates CRON with WEAVE + DYE (no fees)
3. Platform mints DYE and corresponding hTUSD (deficit tracking)
4. User spins CRON within 24 hours → creates soulbound WEAVE
5. Backend processes WEAVE → creates FIBER
6. Platform mints hTUSD for actual cost incurred
7. If CRON expires: WEAVE returns to pool, DYE returns to circulation
```

### 4.2 Advertiser Flow
```
1. Advertiser pays: distribution fee + WEAVE cost + DYE cost + TUSD subsidy
2. Platform creates wrapped CRON for target user
3. Platform records distribution fee as TUSD revenue
4. User spins CRON (receives TUSD subsidy)
5. Creates branded FIBER with sponsor metadata
```

### 4.3 Vendor Flow
```
1. Vendor pays: distribution fee + WEAVE cost + DYE cost
2. Vendor wraps hTUSD premium amount in CRON
3. Platform records distribution fee as TUSD revenue
4. User pays hTUSD premium to vendor when spinning
5. Creates premium FIBER with enhanced features
```

### 4.4 Pool Trading Flow
```
1. Pool starts closed, accumulates WEAVE from expired CRONs
2. Once sufficient inventory, admin opens pool
3. Users can swap TUSD for WEAVE at market rate
4. Price floor maintained at DYE price (computational cost)
5. If price drops below floor: mint hTUSD + burn DYE
```

### 4.5 Expiry Compaction with Automatic Balancing
```
1. CRONs expire after 24 hours if not spun
2. No separate expiry transactions needed
3. Any WEAVE→FIBER operation triggers compaction
4. Expired CRONs return WEAVE to pool, DYE to circulation
5. Expired advertiser subsidies (TUSD) automatically:
   - Burn equivalent hTUSD deficit (automatic reconciliation)
   - Excess goes to treasury as platform revenue
   - Tracked in current 6-hour bucket
6. All metrics stored in 8-bucket sliding window (48 hours)
```

## 5. Revenue Model

### 5.1 Revenue Sources
All revenue mints TUSD (never burns hTUSD automatically):

1. **Distribution Fees**: Charged to advertisers/vendors creating CRONs
2. **WEAVE Sales**: From pool trading or direct sales
3. **DYE Sales**: For users wanting more computational units
4. **Premium Features**: Future revenue streams

### 5.2 Cost Tracking
All costs mint hTUSD (never burn automatically):

1. **AI Processing**: Actual OpenAI API costs
2. **Infrastructure**: IPFS, backend operations
3. **Pool Interventions**: Maintaining price floor
4. **Overruns**: When actual cost > expected DYE value

### 5.3 Reconciliation Approach
**Automatic Micro-Reconciliation**:
- Expired advertiser subsidies automatically burn hTUSD
- Happens during normal WEAVE→FIBER operations
- Tracked in 6-hour buckets for analytics
- Continuous deficit reduction

**Manual Monthly Reconciliation**:
- Admin/CFO reviews remaining balances
- Makes strategic decisions on reserves
- Maintains clean books for accounting
- DYE price remains pure cost metric

## 6. Security Considerations

### 6.1 Access Control
```solidity
bytes32 public constant FACTORY_ROLE = keccak256("FACTORY");
bytes32 public constant BACKEND_ROLE = keccak256("BACKEND");
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
bytes32 public constant TREASURY_ROLE = keccak256("TREASURY");
```

### 6.2 Reentrancy Protection
- All state changes before external calls
- OpenZeppelin ReentrancyGuard on critical functions

### 6.3 Integer Overflow
- Solidity 0.8.20+ with built-in overflow protection
- Careful with bit shifting in token IDs

### 6.4 Soulbound Enforcement
- WEAVE tokens check transfers in _update hook
- Revert all transfers except minting

## 7. Gas Optimization

### 7.1 Storage Packing
```solidity
struct OptimizedCRON {
    uint16 providerId;     // Slot 1: 2 bytes
    uint80 dyeAmount;      // Slot 1: 10 bytes  
    uint32 expiryTime;     // Slot 1: 4 bytes (timestamp)
    uint128 monetaryValue; // Slot 2: 16 bytes
    address sponsor;       // Slot 3: 20 bytes
    bool isSubsidy;        // Slot 3: 1 byte
    // Total: 3 slots
}
```

### 7.2 Batch Operations
- Process multiple expired CRONs in one transaction
- Batch FIBER minting for backend

### 7.3 Event-Based Storage
- Store metadata in events when possible
- Keep only essential data in contract storage

## 8. Launch Sequence

### Phase 1: Soft Launch (Weeks 1-2)
1. Deploy all contracts with pool closed
2. Enable entitlements only
3. Gather cost data from operations
4. Let WEAVE inventory build from expiries

### Phase 2: Pool Opening (Week 3)
1. Analyze DYE price stability
2. Ensure sufficient WEAVE inventory
3. Open SimpleCRONPool for trading
4. Monitor price floor mechanism

### Phase 3: Sponsor Integration (Week 4)
1. Enable advertiser CRON creation
2. Enable vendor CRON creation
3. Test distribution fee collection
4. Verify subsidy/premium flows

### Phase 4: Full Production (Week 5+)
1. All features operational
2. Monthly reconciliation begins
3. Continuous monitoring
4. Feature expansion

## 9. Testing Requirements

### 9.1 Unit Tests
- Token minting/burning mechanics
- CRON expiry after 24 hours
- Soulbound WEAVE enforcement
- DYE price calculation
- Pool price floor maintenance

### 9.2 Integration Tests
- Full entitlement → FIBER flow
- Advertiser subsidy flow
- Vendor premium flow
- Pool trading with floor
- Expiry compaction

### 9.3 Economic Tests
- DYE price tracking accuracy
- hTUSD/TUSD balance tracking
- Price floor interventions
- Revenue recording
- Cost overrun handling

### 9.4 Security Tests
- Reentrancy attempts
- Access control bypass attempts
- Integer overflow edge cases
- Soulbound transfer attempts

## 10. Deployment Configuration

### 10.1 Initial Parameters
```solidity
CRON_DURATION = 24 hours
ENTITLEMENT_INTERVAL = 6 hours
INITIAL_DYE_PRICE = 0.05 * 1e6  // $0.05 in TUSD decimals
MIN_WEAVE_LIQUIDITY = 100       // Minimum before pool opens
PROVIDER_ID_OPENAI = 1          // OpenAI as first provider
```

### 10.2 Role Assignments
```solidity
DEFAULT_ADMIN_ROLE -> Multisig
FACTORY_ROLE -> WeaveFactory
BACKEND_ROLE -> Backend server wallet
TREASURY_ROLE -> Treasury contract
MINTER_ROLE -> Authorized contracts only
```

### 10.3 Contract Addresses (To be filled on deployment)
```
CRONToken: 0x...
WEAVEToken: 0x...
FIBERToken: 0x...
DYEToken: 0x...
TUSDToken: 0x...
hTUSDToken: 0x...
WeaveFactory: 0x...
EntitlementManager: 0x...
ProviderRegistry: 0x...
SimpleCRONPool: 0x...
Treasury: 0x...
```

## 11. Monitoring & Analytics

### 11.1 Key Metrics
- Total users with FIBERs
- Daily CRON creation/expiry rate
- DYE price trend
- hTUSD deficit vs TUSD revenue
- Pool WEAVE inventory
- Price floor intervention frequency

### 11.2 Events for Indexing
```solidity
event CRONCreated(uint256 indexed tokenId, address indexed recipient, uint256 expiry);
event CRONSpun(uint256 indexed cronId, uint256 indexed weaveId, address indexed user);
event CRONExpired(uint256 indexed cronId, uint256 weaveReturned);
event FIBERCreated(uint256 indexed fiberId, address indexed creator, uint256 cost);
event PriceFloorMaintained(uint256 htusdMinted, uint256 dyeBurned);
event MonthlyReconciliation(uint256 amount, uint256 timestamp);
```

## 12. Future Considerations

### 12.1 Additional Providers
- Provider ID 2: Anthropic Claude
- Provider ID 3: Stability AI
- Provider ID 4: Midjourney
- Different DYE costs per provider

### 12.2 Enhanced Features
- FIBER collections and series
- Collaborative FIBERs (multiple WEAVEs)
- FIBER evolution/upgrades
- Social features and sharing

### 12.3 Cross-chain Expansion
- Bridge to Ethereum mainnet
- Other L2 deployments
- Cross-chain FIBER transfers

## Appendix A: Contract Interfaces

### ICRON
```solidity
interface ICRON {
    function mint(address to, CRONData memory data) external returns (uint256);
    function spin(uint256 tokenId) external;
    function isExpired(uint256 tokenId) external view returns (bool);
    function processExpired(uint256[] calldata tokenIds) external;
}
```

### IWEAVE
```solidity
interface IWEAVE {
    function mint(address to, uint256 cronId, bytes memory metadata) external returns (uint256);
    function burn(uint256 tokenId) external;
    function isLocked(uint256 tokenId) external view returns (bool);
}
```

### IFIBER
```solidity
interface IFIBER {
    function mint(
        address to,
        uint256 weaveId,
        string memory ipfsHash,
        uint256 actualCost
    ) external returns (uint256);
}
```

## Appendix B: Error Codes

```solidity
error InsufficientBalance(uint256 requested, uint256 available);
error CRONExpired(uint256 cronId);
error CRONNotExpired(uint256 cronId);
error WEAVELocked(uint256 weaveId);
error EntitlementTooSoon(uint256 nextClaim);
error PoolClosed();
error PriceBelowFloor(uint256 current, uint256 floor);
error Unauthorized(address caller);
```

---

*This Technical Design Document represents the complete and final protocol specification for implementation.*