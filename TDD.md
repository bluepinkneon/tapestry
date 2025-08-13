# Technical Design Document: Weave Ecosystem

**Version**: 1.0  
**Date**: August 13, 2025  
**Authors**: Development Team  
**Status**: Final Design

## 1. Introduction

### 1.1 Purpose
This document provides the comprehensive technical design for the Weave ecosystem on Tapestry L2 blockchain, detailing smart contract architecture, token mechanics, economic flows, and implementation specifications.

### 1.2 Scope
- Smart contract specifications
- Token implementations
- Economic mechanisms
- Backend integration requirements
- Security considerations
- Gas optimization strategies

### 1.3 Definitions
- **CRON**: Time-wrapped bundle containing WEAVE + DYE + [USDC/hUSDC]
- **WEAVE**: Soulbound token representing creation rights
- **FIBER**: Final NFT output (comic-style journal entry)
- **DYE**: Computational units for processing
- **hUSDC**: USD hole tracking platform deficit
- **Spinning**: The act of unwrapping CRON to access WEAVE

## 2. System Architecture

### 2.1 High-Level Overview
```
┌─────────────────────────────────────────────────────────┐
│                     Tapestry L2                          │
├─────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │   CRON   │→ │  WEAVE   │→ │  FIBER   │  │  DYE   │ │
│  │  Wrapper │  │Soulbound │  │   NFT    │  │ Units  │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
│                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │  hUSDC   │  │   Pool   │  │ Factory  │  │Treasury│ │
│  │  Deficit │  │   AMM    │  │Orchestr. │  │  USDC  │ │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
└─────────────────────────────────────────────────────────┘
                              ↕
┌─────────────────────────────────────────────────────────┐
│                    Backend Services                      │
├─────────────────────────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐ │
│  │  OpenAI  │  │   IPFS   │  │  Oracle  │  │  Queue │ │
│  │    API   │  │  Storage │  │   Cost   │  │ Process│ │
│  └──────────┘  └──────────┘  └──────────┘  └────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Contract Dependencies
```solidity
WeaveFactory (Main)
├── CRONManager
│   ├── WEAVEToken
│   ├── DYEToken
│   └── PricingOracle
├── EntitlementManager
│   └── TimeKeeper
├── SponsorshipManager
│   ├── AdvertiserRegistry
│   └── VendorRegistry
├── Treasury
│   ├── hUSDCToken
│   └── USDCInterface
└── SimpleCRONPool
    └── PriceDiscovery
```

## 3. Token Specifications

### 3.1 CRON Token (Wrapper)
```solidity
contract CRONToken {
    struct CRON {
        uint256 id;
        uint256 weaveId;
        uint256 dyeAmount;
        uint256 monetaryValue;    // USDC or hUSDC amount
        bool isSubsidy;           // true = USDC subsidy, false = hUSDC premium
        address recipient;
        address sponsor;
        uint256 expiryTime;
        bytes metadata;           // Sponsor branding/style
    }
    
    mapping(uint256 => CRON) public crons;
    
    // Events
    event CRONCreated(uint256 indexed id, address indexed recipient, uint256 expiry);
    event CRONSpun(uint256 indexed id, address indexed user);
    event CRONExpired(uint256 indexed id, uint256 weaveReturned, uint256 dyeReturned);
}
```

### 3.2 WEAVE Token (Soulbound ERC-721)
```solidity
contract WEAVEToken is ERC721, Soulbound {
    struct WEAVEData {
        uint256 id;
        address owner;
        uint256 createdAt;
        uint256 cronId;           // Source CRON
        SponsorType sponsorType;
        bytes sponsorData;
    }
    
    // Soulbound: Override transfer functions
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(from == address(0), "WEAVE: Soulbound");
    }
    
    function mintSoulbound(address to, uint256 cronId) external returns (uint256);
    function burn(uint256 tokenId) external;
}
```

### 3.3 FIBER Token (ERC-721 NFT)
```solidity
contract FIBERToken is ERC721, ERC721Metadata {
    struct FIBERMetadata {
        uint256 id;
        address creator;
        uint256 createdAt;
        string ipfsHash;          // Comic content
        uint256 dyeUsed;          // Computational units
        uint256 costUSDC;         // Actual cost
        SponsorType sponsorType;
        address sponsor;
        string journalText;       // Original input
    }
    
    mapping(uint256 => FIBERMetadata) public fibers;
    
    function mint(
        address to,
        string memory ipfsHash,
        FIBERMetadata memory metadata
    ) external returns (uint256);
}
```

### 3.4 DYE Token (ERC-20)
```solidity
contract DYEToken is ERC20 {
    // Tracks computational units
    // Minted when wrapped in CRON
    // Burned when CRON is spun
    
    mapping(address => bool) public minters;
    mapping(address => bool) public burners;
    
    function mint(address to, uint256 amount) external onlyMinter;
    function burn(uint256 amount) external onlyBurner;
}
```

### 3.5 hUSDC Token (ERC-20)
```solidity
contract hUSDCToken is ERC20 {
    // Tracks platform deficit (costs incurred)
    // Minted when FIBER created (actual cost)
    // Burned when revenue received
    
    uint256 public totalDeficit;    // Total minted
    uint256 public totalCovered;    // Total burned
    
    function mint(uint256 amount) external onlyFactory {
        _mint(treasury, amount);
        totalDeficit += amount;
    }
    
    function burn(uint256 amount) external {
        _burn(treasury, amount);
        totalCovered += amount;
    }
}
```

## 4. Core Contracts

### 4.1 WeaveFactory (Main Orchestrator)
```solidity
contract WeaveFactory {
    // State variables
    CRONToken public cronToken;
    WEAVEToken public weaveToken;
    FIBERToken public fiberToken;
    DYEToken public dyeToken;
    hUSDCToken public husdcToken;
    IERC20 public usdcToken;
    
    uint256 public constant STANDARD_DYE = 2500;
    uint256 public constant PREMIUM_DYE = 5000;
    uint256 public constant CRON_DURATION = 24 hours;
    
    // Main functions
    function createEntitlementCRON(address user) external;
    function createAdvertiserCRON(address recipient, uint256 subsidy, bytes calldata metadata) external;
    function createVendorCRON(address recipient, uint256 premium, bytes calldata metadata) external;
    function spinCRON(uint256 cronId) external;
    function processExpiredCRON(uint256 cronId) external;
    function completeWEAVE(uint256 weaveId, bool success, uint256 actualCostUSDC, string memory ipfsHash) external;
}
```

### 4.2 EntitlementManager
```solidity
contract EntitlementManager {
    uint256 public constant ENTITLEMENT_INTERVAL = 6 hours;
    uint256 public constant MAX_DAILY_ENTITLEMENTS = 4;
    
    struct UserEntitlement {
        uint256 lastClaim;
        uint256 claimsToday;
        uint256 dayStarted;
    }
    
    mapping(address => UserEntitlement) public entitlements;
    
    function claimEntitlement() external {
        UserEntitlement storage ent = entitlements[msg.sender];
        
        // Reset daily counter if new day
        if (block.timestamp >= ent.dayStarted + 1 days) {
            ent.claimsToday = 0;
            ent.dayStarted = block.timestamp;
        }
        
        require(ent.claimsToday < MAX_DAILY_ENTITLEMENTS, "Daily limit");
        require(block.timestamp >= ent.lastClaim + ENTITLEMENT_INTERVAL, "Too soon");
        
        // Create CRON for user
        weaveFactory.createEntitlementCRON(msg.sender);
        
        ent.lastClaim = block.timestamp;
        ent.claimsToday++;
    }
}
```

### 4.3 DynamicFeeManager
```solidity
contract DynamicFeeManager {
    WeavePool public weavePool;
    
    function calculateDistributionFee(WrapType wType) external view returns (uint256) {
        uint256 poolSize = weavePool.available();
        uint256 utilization = weavePool.getUtilizationRate();
        
        // Base fees
        uint256 baseFee;
        if (wType == WrapType.GIFT) baseFee = 0.1 * 1e6;
        else if (wType == WrapType.ADVERTISER) baseFee = 0.5 * 1e6;
        else if (wType == WrapType.VENDOR) baseFee = 0.3 * 1e6;
        
        // Scarcity multiplier
        uint256 multiplier;
        if (poolSize == 0) {
            // No inventory - value-based pricing
            multiplier = 200; // 2x
        } else if (utilization > 95) {
            // Critical scarcity
            multiplier = 500; // 5x
        } else if (utilization > 90) {
            // High utilization
            multiplier = 200; // 2x
        } else if (utilization > 80) {
            // Normal
            multiplier = 100; // 1x
        } else {
            // Abundant
            multiplier = 50; // 0.5x
        }
        
        return (baseFee * multiplier) / 100;
    }
}
```

### 4.4 SimpleCRONPool (AMM)
```solidity
contract SimpleCRONPool {
    uint256 public weaveReserve;
    uint256 public usdcReserve;
    
    // No fees, pure ratio
    function getPrice() public view returns (uint256) {
        if (weaveReserve == 0) return 1e6; // $1 default
        return (usdcReserve * 1e18) / weaveReserve;
    }
    
    function swapUSDCForWEAVE(uint256 usdcIn) external returns (uint256 weaveOut) {
        uint256 k = weaveReserve * usdcReserve;
        uint256 newUsdcReserve = usdcReserve + usdcIn;
        uint256 newWeaveReserve = k / newUsdcReserve;
        weaveOut = weaveReserve - newWeaveReserve;
        
        // Update reserves
        usdcReserve = newUsdcReserve;
        weaveReserve = newWeaveReserve;
        
        // Transfer tokens
        usdcToken.transferFrom(msg.sender, address(this), usdcIn);
        weaveToken.transfer(msg.sender, weaveOut);
    }
}
```

## 5. Economic Flows

### 5.1 Entitlement Flow
```
1. User claims entitlement (every 6 hours)
2. System creates CRON(WEAVE + DYE)
3. User spins CRON within 24 hours
4. Creates soulbound WEAVE, burns DYE
5. Backend processes with AI
6. WEAVE burns → FIBER minted + hUSDC minted
```

### 5.2 Advertiser Flow
```
1. Advertiser creates wrapped CRONs
   - Pays: Distribution fee + WEAVE price + DYE cost + Subsidy
2. User claims advertiser CRON
3. User spins (free or profitable)
4. Subsidy USDC burns equivalent hUSDC (deficit reduction!)
5. Creates branded FIBER
```

### 5.3 Vendor Flow  
```
1. Vendor creates premium CRONs
   - Pays: Distribution fee + WEAVE price + DYE cost
2. User buys and spins vendor CRON
   - Pays: Premium amount
3. Platform keeps DYE cost from premium
4. Vendor receives (Premium - DYE cost)
5. Creates premium FIBER
```

### 5.4 Expiry Flow
```
1. CRON not spun within 24 hours
2. WEAVE returns to pool (becomes inventory)
3. DYE returns to pool
4. Any wrapped USDC/hUSDC is lost
5. Distribution fees never refunded
```

## 6. Backend Integration

### 6.1 Event Listeners
```javascript
// Listen for WEAVE creation
contract.on('WEAVECreated', async (weaveId, owner) => {
  const journalData = await getJournalData(owner);
  const job = await queue.add('processWeave', {
    weaveId,
    owner,
    journalData
  });
});

// Process WEAVE
async function processWeave(job) {
  const { weaveId, journalData } = job.data;
  
  try {
    // Generate comic with AI
    const result = await generateComic(journalData);
    
    // Upload to IPFS
    const ipfsHash = await ipfs.add(result.image);
    
    // Report to contract
    await contract.completeWEAVE(
      weaveId,
      true,                    // success
      result.costUSDC * 1e6,   // actual cost in USDC decimals
      ipfsHash
    );
  } catch (error) {
    // Report failure
    await contract.completeWEAVE(
      weaveId,
      false,                   // failed
      error.costUSDC * 1e6,    // cost still incurred
      ''
    );
  }
}
```

### 6.2 Cost Tracking
```javascript
// Track costs accurately
async function generateComic(journalData) {
  const startTime = Date.now();
  let totalCost = 0;
  let attempts = 0;
  
  while (attempts < 3) {
    try {
      const response = await openai.createCompletion({
        model: 'gpt-4',
        prompt: formatPrompt(journalData),
        max_tokens: 1000
      });
      
      // Calculate cost
      const promptTokens = response.usage.prompt_tokens;
      const completionTokens = response.usage.completion_tokens;
      const textCost = calculateCost(promptTokens, completionTokens);
      
      // Generate image
      const image = await generateImage(response.choices[0].text);
      const imageCost = 0.04; // DALL-E cost
      
      totalCost += textCost + imageCost;
      
      return {
        success: true,
        image,
        costUSDC: totalCost,
        attempts: attempts + 1
      };
    } catch (error) {
      totalCost += 0.01; // Failed attempt cost
      attempts++;
    }
  }
  
  throw { costUSDC: totalCost, message: 'Max attempts reached' };
}
```

## 7. Security Considerations

### 7.1 Access Control
```solidity
contract WeaveFactory {
    mapping(address => bool) public backends;
    mapping(address => bool) public oracles;
    
    modifier onlyBackend() {
        require(backends[msg.sender], "Not backend");
        _;
    }
    
    modifier onlyOracle() {
        require(oracles[msg.sender], "Not oracle");
        _;
    }
}
```

### 7.2 Reentrancy Protection
```solidity
contract WeaveFactory is ReentrancyGuard {
    function spinCRON(uint256 cronId) external nonReentrant {
        // Process CRON spinning
    }
    
    function claimAdvertiserCRON(uint256 cronId) external nonReentrant {
        // Process claiming
    }
}
```

### 7.3 Integer Overflow Protection
- Use Solidity 0.8.x with built-in overflow protection
- Use OpenZeppelin SafeMath for older versions

### 7.4 Oracle Security
```solidity
contract PriceOracle {
    uint256 public lastUpdate;
    uint256 public maxAge = 1 hours;
    
    function updatePrice(uint256 newPrice) external onlyOracle {
        require(block.timestamp >= lastUpdate + 1 minutes, "Too frequent");
        require(newPrice > 0 && newPrice < 1000 * 1e6, "Invalid price");
        
        lastUpdate = block.timestamp;
        currentPrice = newPrice;
    }
    
    function getPrice() external view returns (uint256) {
        require(block.timestamp <= lastUpdate + maxAge, "Price stale");
        return currentPrice;
    }
}
```

## 8. Gas Optimization

### 8.1 Storage Optimization
```solidity
// Pack struct variables
struct CRON {
    uint128 weaveId;      // Sufficient for ID
    uint128 dyeAmount;    // Sufficient for DYE
    uint64 expiryTime;    // Sufficient for timestamp
    uint64 monetaryValue; // Sufficient for reasonable USDC
    address recipient;    // 20 bytes
    bool isSubsidy;       // 1 byte
    // Total: 2 storage slots instead of 6
}
```

### 8.2 Batch Operations
```solidity
function processExpiredCRONBatch(uint256[] calldata cronIds) external {
    for (uint i = 0; i < cronIds.length; i++) {
        if (isExpired(cronIds[i])) {
            _processExpiredCRON(cronIds[i]);
        }
    }
}
```

### 8.3 Event Optimization
```solidity
// Use indexed parameters for frequently queried fields
event CRONCreated(
    uint256 indexed cronId,
    address indexed recipient,
    address indexed sponsor,
    uint256 expiry
);
```

## 9. Testing Strategy

### 9.1 Unit Tests
```javascript
describe("CRON Token", () => {
  it("should create CRON with correct expiry", async () => {
    const tx = await cronToken.createCRON(user.address);
    const cron = await cronToken.getCRON(1);
    
    expect(cron.expiryTime).to.equal(
      (await ethers.provider.getBlock()).timestamp + 86400
    );
  });
  
  it("should return WEAVE to pool on expiry", async () => {
    await time.increase(86401); // 24 hours + 1 second
    await cronToken.processExpiredCRON(1);
    
    expect(await weavePool.available()).to.equal(1);
  });
});
```

### 9.2 Integration Tests
```javascript
describe("Full Flow", () => {
  it("should complete entitlement to FIBER flow", async () => {
    // Claim entitlement
    await entitlementManager.claimEntitlement();
    
    // Spin CRON
    await weaveFactory.spinCRON(1);
    
    // Simulate backend processing
    await weaveFactory.connect(backend).completeWEAVE(
      1,
      true,
      50000, // $0.05 cost
      "ipfs://Qm..."
    );
    
    // Verify FIBER created
    expect(await fiberToken.ownerOf(1)).to.equal(user.address);
    
    // Verify hUSDC minted
    expect(await husdcToken.totalSupply()).to.equal(50000);
  });
});
```

### 9.3 Economic Tests
```javascript
describe("Economic Model", () => {
  it("should reduce deficit with advertiser subsidy", async () => {
    const initialDeficit = await husdcToken.totalSupply();
    
    // Create advertiser CRON with $1 subsidy
    await advertiserManager.createCRON(user.address, 1e6);
    
    // User spins
    await weaveFactory.connect(user).spinCRON(1);
    
    // Complete FIBER
    await weaveFactory.connect(backend).completeWEAVE(1, true, 50000, "ipfs://");
    
    // Deficit should be reduced by (subsidy - cost)
    const newDeficit = await husdcToken.totalSupply();
    expect(initialDeficit - newDeficit).to.equal(950000); // $0.95 reduction
  });
});
```

## 10. Deployment Strategy

### 10.1 Deployment Order
1. Deploy token contracts (DYE, hUSDC)
2. Deploy WEAVEToken (soulbound)
3. Deploy FIBERToken (NFT)
4. Deploy SimpleCRONPool
5. Deploy EntitlementManager
6. Deploy DynamicFeeManager
7. Deploy WeaveFactory (main)
8. Configure permissions and roles
9. Initialize pools with liquidity

### 10.2 Configuration Script
```javascript
async function deploy() {
  // Deploy tokens
  const DYE = await ethers.deployContract("DYEToken");
  const hUSDC = await ethers.deployContract("hUSDCToken");
  const WEAVE = await ethers.deployContract("WEAVEToken");
  const FIBER = await ethers.deployContract("FIBERToken");
  
  // Deploy core contracts
  const Factory = await ethers.deployContract("WeaveFactory", [
    DYE.address,
    hUSDC.address,
    WEAVE.address,
    FIBER.address,
    USDC_ADDRESS
  ]);
  
  // Configure permissions
  await DYE.grantRole(MINTER_ROLE, Factory.address);
  await hUSDC.grantRole(MINTER_ROLE, Factory.address);
  await WEAVE.grantRole(MINTER_ROLE, Factory.address);
  await FIBER.grantRole(MINTER_ROLE, Factory.address);
  
  // Initialize pools
  await Pool.initialize(1000, 1000e6); // 1000 WEAVE, $1000 USDC
  
  console.log("Deployment complete!");
}
```

## 11. Monitoring and Analytics

### 11.1 Key Metrics
```solidity
contract Analytics {
    struct Metrics {
        uint256 totalUsers;
        uint256 totalFIBERsCreated;
        uint256 utilizationRate;
        uint256 expiryRate;
        uint256 totalDeficit;
        uint256 totalRevenue;
        uint256 averageDyePerFiber;
        uint256 averageCostPerFiber;
    }
    
    function getMetrics() external view returns (Metrics memory);
    function getDailyStats(uint256 day) external view returns (DailyStats memory);
    function getUserStats(address user) external view returns (UserStats memory);
}
```

### 11.2 Event Indexing
```graphql
type CRON @entity {
  id: ID!
  recipient: User!
  sponsor: Sponsor
  createdAt: BigInt!
  expiryTime: BigInt!
  status: CRONStatus!
  weaveId: BigInt!
  dyeAmount: BigInt!
}

type FIBER @entity {
  id: ID!
  creator: User!
  createdAt: BigInt!
  ipfsHash: String!
  dyeUsed: BigInt!
  costUSDC: BigInt!
  sponsor: Sponsor
}

type User @entity {
  id: ID!
  totalFIBERs: BigInt!
  totalCRONsClaimed: BigInt!
  totalCRONsExpired: BigInt!
}
```

## 12. Upgrade Strategy

### 12.1 Upgradeable Contracts
```solidity
contract WeaveFactoryV2 is WeaveFactoryV1, UUPSUpgradeable {
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyRole(UPGRADER_ROLE) 
    {}
    
    function version() public pure returns (string memory) {
        return "2.0.0";
    }
}
```

### 12.2 Migration Plan
1. Deploy new implementation
2. Pause old factory
3. Migrate state if needed
4. Update proxy to new implementation
5. Resume operations
6. Monitor for issues

## 13. Risk Analysis

### 13.1 Technical Risks
- **Smart Contract Bugs**: Mitigated by audits and testing
- **Oracle Failures**: Fallback to manual updates
- **Backend Failures**: Queue system with retries
- **IPFS Availability**: Backup storage options

### 13.2 Economic Risks
- **100% Utilization**: Platform pivots to value marketplace
- **0% Utilization**: Minimum distribution fees ensure revenue
- **Price Manipulation**: AMM pool with protective mechanisms
- **Deficit Spiral**: Advertiser subsidies reduce deficit

### 13.3 Operational Risks
- **Regulatory**: Utility token model, not security
- **Scalability**: L2 solution for gas efficiency
- **User Adoption**: Free entitlements drive usage
- **Competition**: First mover advantage, network effects

## 14. Conclusion

The Weave ecosystem technical design provides a robust, scalable, and economically sustainable platform for transforming journal entries into NFT comics. The key innovations include:

1. **Dual-token cost tracking** (DYE for operations, hUSDC for costs)
2. **Expired inventory monetization** (waste becomes product)
3. **Deficit reduction via subsidies** (advertisers pay platform costs)
4. **Resilient at any utilization** (works from 0% to 100%)

The system is designed to be self-balancing, requiring minimal manual intervention while providing transparent on-chain economics for all participants.

---

*This technical design document is subject to updates based on implementation findings and community feedback.*