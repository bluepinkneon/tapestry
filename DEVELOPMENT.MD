# Weave Ecosystem Development Guide

**Version**: 2.0  
**Date**: August 13, 2025  
**Purpose**: Technical development guide for implementing the Weave ecosystem smart contracts

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Technology Stack](#technology-stack)
3. [Contract Structure](#contract-structure)
4. [Implementation Patterns](#implementation-patterns)
5. [Security Best Practices](#security-best-practices)
6. [Gas Optimization](#gas-optimization)
7. [Development Workflow](#development-workflow)
8. [Testing Strategy](#testing-strategy)
9. [Deployment Guide](#deployment-guide)

## Architecture Overview

### Design Philosophy
The Weave ecosystem uses a **simple, modular architecture** optimized for clarity and gas efficiency. We explicitly avoid complex patterns like Diamond Standard in favor of straightforward, auditable contracts.

### System Architecture
```
┌─────────────────────────────────────────────────┐
│                 WeaveFactory                     │
│          (Main Orchestrator Contract)            │
└────────────────┬─────────────────────────────────┘
                 │
    ┌────────────┼────────────┬──────────┬─────────┐
    ▼            ▼            ▼          ▼         ▼
┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐  ┌────────┐
│  CRON  │  │ WEAVE  │  │ FIBER  │  │  DYE   │  │  TUSD  │
│ERC-721 │  │ERC-1155│  │ERC-1155│  │ ERC-20 │  │ ERC-20 │
└────────┘  └────────┘  └────────┘  └────────┘  └────────┘
                                                      │
                                                 ┌────────┐
                                                 │ hTUSD  │
                                                 │ ERC-20 │
                                                 └────────┘

┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│  Entitlement    │  │     Provider    │  │   SimpleCRON    │
│    Manager      │  │     Registry    │  │      Pool       │
└─────────────────┘  └─────────────────┘  └─────────────────┘

┌─────────────────────────────────────────────────┐
│                   Treasury                       │
│            (Revenue & Deficit Management)        │
└─────────────────────────────────────────────────┘
```

### Contract Categories

#### Immutable Contracts
These contracts are deployed once and never upgraded:
- **Token Contracts**: DYE, TUSD, hTUSD, CRON, WEAVE, FIBER
- **Core Logic**: SimpleCRONPool, EntitlementManager

#### Upgradeable Contracts
Using UUPS pattern for future flexibility:
- **WeaveFactory**: Main orchestration logic
- **Treasury**: Financial management
- **ProviderRegistry**: AI provider management

## Technology Stack

### Core Dependencies
```bash
# Solidity version
pragma solidity ^0.8.20;

# OpenZeppelin Contracts v5.0
forge install OpenZeppelin/openzeppelin-contracts

# Development framework
Foundry (Forge, Cast, Anvil)
```

### Project Setup
```bash
# Initialize project
forge init --no-commit
cd tapestry

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts

# Configure remappings
echo '@openzeppelin/=lib/openzeppelin-contracts/' > remappings.txt
```

### Configuration (foundry.toml)
```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.20"
optimizer = true
optimizer_runs = 200

[profile.production]
optimizer_runs = 10000
via_ir = true
```

## Contract Structure

### Token Contracts

#### CRONToken.sol
```solidity
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract CRONToken is ERC721, AccessControl {
    struct CRONData {
        uint16 providerId;
        uint240 dyeAmount;
        uint256 monetaryValue;
        bool isSubsidy;
        address sponsor;
        uint256 expiryTime;
        bytes metadata;
    }
    
    mapping(uint256 => CRONData) public cronData;
    uint256 private _nextTokenId;
    
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY");
    
    function mint(address to, CRONData memory data) 
        external 
        onlyRole(FACTORY_ROLE) 
        returns (uint256) 
    {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        cronData[tokenId] = data;
        cronData[tokenId].expiryTime = block.timestamp + 24 hours;
        return tokenId;
    }
}
```

#### WEAVEToken.sol (Soulbound)
```solidity
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract WEAVEToken is ERC1155, AccessControl {
    // Token ID = (providerId << 240) | uniqueId
    uint256 private _nextUniqueId;
    
    struct WEAVEData {
        uint256 cronId;
        address creator;
        uint256 createdAt;
        bytes sponsorData;
    }
    
    mapping(uint256 => WEAVEData) public weaveData;
    
    // Override transfer to enforce soulbound
    function _update(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values
    ) internal override {
        require(from == address(0), "WEAVE: Soulbound token");
        super._update(from, to, ids, values);
    }
}
```

### Core Logic Contracts

#### WeaveFactory.sol
```solidity
contract WeaveFactory is AccessControl, ReentrancyGuard {
    // State variables
    CRONToken public immutable cronToken;
    WEAVEToken public immutable weaveToken;
    FIBERToken public immutable fiberToken;
    DYEToken public immutable dyeToken;
    hTUSDToken public immutable htusdToken;
    TUSDToken public immutable tusdToken;
    
    ProviderRegistry public providerRegistry;
    EntitlementManager public entitlementManager;
    SimpleCRONPool public pool;
    Treasury public treasury;
    
    // Constants
    uint256 public constant INITIAL_DYE_PRICE = 0.05e6; // $0.05
    
    // Events
    event CRONCreated(uint256 indexed tokenId, address indexed recipient);
    event WEAVECreated(uint256 indexed weaveId, address indexed creator);
    event FIBERCompleted(uint256 indexed fiberId, uint256 cost);
    
    // Main functions
    function createEntitlementCRON(address recipient) external {
        // Get DYE amount from provider registry
        uint256 dyeAmount = providerRegistry.getBaseDyeAmount(1); // OpenAI
        
        // Mint DYE
        dyeToken.mint(address(this), dyeAmount);
        
        // Calculate and mint hTUSD for deficit tracking
        uint256 dyePrice = _getDYEPrice();
        uint256 htusdAmount = (dyeAmount * dyePrice) / 1e18;
        htusdToken.mint(htusdAmount);
        
        // Get or mint WEAVE
        uint256 weaveId = _obtainWEAVE();
        
        // Create CRON
        CRONData memory data = CRONData({
            providerId: 1,
            dyeAmount: dyeAmount,
            monetaryValue: 0,
            isSubsidy: false,
            sponsor: address(0),
            expiryTime: 0, // Set by CRON contract
            metadata: ""
        });
        
        uint256 cronId = cronToken.mint(recipient, data);
        emit CRONCreated(cronId, recipient);
    }
    
    function spinCRON(uint256 cronId) external nonReentrant {
        require(cronToken.ownerOf(cronId) == msg.sender, "Not owner");
        CRONData memory data = cronToken.getCRONData(cronId);
        require(block.timestamp < data.expiryTime, "Expired");
        
        // Burn CRON
        cronToken.burn(cronId);
        
        // Burn DYE
        dyeToken.burn(data.dyeAmount);
        
        // Create soulbound WEAVE
        uint256 weaveId = _createWEAVE(msg.sender, cronId, data);
        
        // Handle monetary value
        if (data.monetaryValue > 0) {
            if (data.isSubsidy) {
                // User receives TUSD subsidy
                tusdToken.transfer(msg.sender, data.monetaryValue);
            } else {
                // User pays hTUSD premium to vendor
                require(htusdToken.balanceOf(msg.sender) >= data.monetaryValue);
                htusdToken.transferFrom(msg.sender, data.sponsor, data.monetaryValue);
            }
        }
        
        emit WEAVECreated(weaveId, msg.sender);
    }
}
```

#### SimpleCRONPool.sol
```solidity
contract SimpleCRONPool is AccessControl {
    uint256 public weaveReserve;
    uint256 public tusdReserve;
    bool public poolOpen;
    
    WeaveFactory public factory;
    DYEToken public dyeToken;
    hTUSDToken public htusdToken;
    
    modifier whenOpen() {
        require(poolOpen, "Pool closed");
        _;
    }
    
    function addWEAVE(uint256 amount) external onlyRole(FACTORY_ROLE) {
        weaveReserve += amount;
    }
    
    function openPool() external onlyRole(ADMIN_ROLE) {
        require(weaveReserve >= 100, "Insufficient inventory");
        poolOpen = true;
    }
    
    function getPrice() public view returns (uint256) {
        if (weaveReserve == 0) return getDYEPrice();
        return (tusdReserve * 1e18) / weaveReserve;
    }
    
    function getDYEPrice() public view returns (uint256) {
        uint256 htusdSupply = htusdToken.totalSupply();
        uint256 dyeSupply = dyeToken.totalSupply();
        
        if (dyeSupply == 0) return factory.INITIAL_DYE_PRICE();
        return (htusdSupply * 1e18) / dyeSupply;
    }
    
    function swapTUSDForWEAVE(uint256 tusdAmount) 
        external 
        whenOpen 
        returns (uint256) 
    {
        // Standard AMM swap logic
        uint256 k = weaveReserve * tusdReserve;
        uint256 newTusdReserve = tusdReserve + tusdAmount;
        uint256 newWeaveReserve = k / newTusdReserve;
        uint256 weaveOut = weaveReserve - newWeaveReserve;
        
        // Update reserves
        tusdReserve = newTusdReserve;
        weaveReserve = newWeaveReserve;
        
        // Transfer tokens
        tusdToken.transferFrom(msg.sender, address(this), tusdAmount);
        _transferWEAVE(msg.sender, weaveOut);
        
        // Check and maintain price floor
        _maintainPriceFloor();
        
        return weaveOut;
    }
    
    function _maintainPriceFloor() private {
        uint256 dyePrice = getDYEPrice();
        uint256 poolPrice = getPrice();
        
        if (poolPrice < dyePrice) {
            uint256 deficit = (weaveReserve * dyePrice / 1e18) - tusdReserve;
            
            // Mint hTUSD to track cost
            htusdToken.mint(deficit);
            
            // Burn DYE to maintain price
            uint256 dyeToBurn = deficit * 1e18 / dyePrice;
            dyeToken.burn(dyeToBurn);
            
            // Add TUSD to pool
            tusdReserve += deficit;
            
            emit PriceFloorMaintained(deficit, dyeToBurn);
        }
    }
}
```

## Implementation Patterns

### Custom Errors (Gas Efficient)
```solidity
error InsufficientBalance(uint256 requested, uint256 available);
error CRONExpired(uint256 cronId, uint256 expiredAt);
error Unauthorized(address caller);
error PoolClosed();
error WEAVESoulbound();

// Usage
if (balance < amount) {
    revert InsufficientBalance(amount, balance);
}
```

### Packed Structs
```solidity
struct PackedCRONData {
    uint16 providerId;      // 2 bytes
    uint80 dyeAmount;       // 10 bytes
    uint32 expiryOffset;    // 4 bytes - seconds from creation
    // Total: 16 bytes = 1 slot
    
    uint128 monetaryValue;  // 16 bytes
    uint128 sponsorLower;   // Lower 16 bytes of address
    // Total: 32 bytes = 1 slot
    
    uint32 sponsorUpper;    // Upper 4 bytes of address
    bool isSubsidy;         // 1 byte
    // Metadata stored separately
}
```

### Modifiers Pattern
```solidity
modifier onlyActiveCRON(uint256 cronId) {
    require(cronToken.ownerOf(cronId) != address(0), "CRON does not exist");
    require(!cronToken.isExpired(cronId), "CRON expired");
    _;
}

modifier onlyBackend() {
    require(hasRole(BACKEND_ROLE, msg.sender), "Not backend");
    _;
}
```

## Security Best Practices

### Access Control Hierarchy
```solidity
contract SecureFactory {
    bytes32 public constant ADMIN_ROLE = 0x00;
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY");
    bytes32 public constant BACKEND_ROLE = keccak256("BACKEND");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY");
    
    constructor() {
        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(FACTORY_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BACKEND_ROLE, ADMIN_ROLE);
        _setRoleAdmin(TREASURY_ROLE, ADMIN_ROLE);
    }
}
```

### Reentrancy Protection
```solidity
contract NonReentrant {
    uint256 private _status = 1;
    
    modifier nonReentrant() {
        require(_status == 1, "Reentrant call");
        _status = 2;
        _;
        _status = 1;
    }
}
```

### Pull Payment Pattern
```solidity
mapping(address => uint256) private _pendingPayments;

function withdraw() external nonReentrant {
    uint256 payment = _pendingPayments[msg.sender];
    require(payment > 0, "No payment pending");
    
    _pendingPayments[msg.sender] = 0;
    
    (bool success, ) = msg.sender.call{value: payment}("");
    require(success, "Transfer failed");
}
```

## Gas Optimization

### Batch Operations
```solidity
function processExpiredCRONBatch(uint256[] calldata cronIds) external {
    uint256 length = cronIds.length;
    for (uint256 i; i < length;) {
        if (cronToken.isExpired(cronIds[i])) {
            _processExpiredCRON(cronIds[i]);
        }
        unchecked { ++i; }
    }
}
```

### Storage vs Memory
```solidity
// Bad: Multiple storage reads
function calculateTotal() external view returns (uint256) {
    return userBalance[msg.sender] + userBalance[msg.sender] * rate;
}

// Good: Single storage read
function calculateTotal() external view returns (uint256) {
    uint256 balance = userBalance[msg.sender];
    return balance + balance * rate;
}
```

### Events for Data
```solidity
// Store only essential data in storage
struct MinimalFIBER {
    address creator;
    uint256 createdAt;
}

// Emit detailed data in events
event FIBERCreated(
    uint256 indexed fiberId,
    address indexed creator,
    string ipfsHash,
    uint256 dyeUsed,
    uint256 actualCost,
    bytes metadata
);
```

## Development Workflow

### Project Structure
```
tapestry/
├── src/
│   ├── tokens/
│   │   ├── CRONToken.sol
│   │   ├── WEAVEToken.sol
│   │   ├── FIBERToken.sol
│   │   ├── DYEToken.sol
│   │   ├── TUSDToken.sol
│   │   └── hTUSDToken.sol
│   ├── core/
│   │   ├── WeaveFactory.sol
│   │   ├── EntitlementManager.sol
│   │   ├── ProviderRegistry.sol
│   │   └── Treasury.sol
│   ├── pools/
│   │   └── SimpleCRONPool.sol
│   └── interfaces/
│       ├── ICRON.sol
│       ├── IWEAVE.sol
│       └── IFIBER.sol
├── test/
│   ├── unit/
│   ├── integration/
│   └── invariant/
├── script/
│   ├── Deploy.s.sol
│   └── Configure.s.sol
└── foundry.toml
```

### Development Commands
```bash
# Build
forge build

# Test
forge test -vvv

# Gas report
forge test --gas-report

# Coverage
forge coverage

# Deploy locally
forge script script/Deploy.s.sol --rpc-url localhost --broadcast

# Verify contract
forge verify-contract ADDRESS ContractName --chain-id 1
```

## Testing Strategy

### Unit Tests
```solidity
contract CRONTokenTest is Test {
    CRONToken cron;
    address alice = makeAddr("alice");
    
    function setUp() public {
        cron = new CRONToken();
        cron.grantRole(cron.FACTORY_ROLE(), address(this));
    }
    
    function test_MintCRON() public {
        CRONData memory data = _getCRONData();
        uint256 tokenId = cron.mint(alice, data);
        
        assertEq(cron.ownerOf(tokenId), alice);
        assertEq(cron.cronData(tokenId).dyeAmount, data.dyeAmount);
    }
    
    function test_CRONExpiry() public {
        uint256 tokenId = cron.mint(alice, _getCRONData());
        
        vm.warp(block.timestamp + 24 hours + 1);
        assertTrue(cron.isExpired(tokenId));
    }
}
```

### Integration Tests
```solidity
contract EntitlementFlowTest is Test {
    WeaveEcosystem ecosystem;
    
    function test_FullEntitlementFlow() public {
        address user = makeAddr("user");
        
        // Claim entitlement
        vm.prank(user);
        ecosystem.claimEntitlement();
        
        // Spin CRON
        vm.prank(user);
        ecosystem.spinCRON(1);
        
        // Backend processes
        vm.prank(backend);
        ecosystem.completeWEAVE(1, true, 50000, "ipfs://");
        
        // Verify FIBER created
        assertEq(ecosystem.fiberToken().balanceOf(user, 1), 1);
    }
}
```

### Invariant Tests
```solidity
contract InvariantTest is Test {
    function invariant_DYEPriceAlwaysPositive() public {
        uint256 price = pool.getDYEPrice();
        assertTrue(price > 0);
    }
    
    function invariant_NoNegativeBalances() public {
        assertTrue(address(treasury).balance >= 0);
    }
}
```

## Deployment Guide

### Deployment Script
```solidity
// script/Deploy.s.sol
contract DeployScript is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        
        // Deploy tokens
        DYEToken dye = new DYEToken();
        TUSDToken tusd = new TUSDToken();
        hTUSDToken htusd = new hTUSDToken();
        CRONToken cron = new CRONToken();
        WEAVEToken weave = new WEAVEToken();
        FIBERToken fiber = new FIBERToken();
        
        // Deploy core
        ProviderRegistry registry = new ProviderRegistry();
        EntitlementManager entitlements = new EntitlementManager();
        SimpleCRONPool pool = new SimpleCRONPool();
        Treasury treasury = new Treasury();
        
        // Deploy factory
        WeaveFactory factory = new WeaveFactory(
            address(cron),
            address(weave),
            address(fiber),
            address(dye),
            address(tusd),
            address(htusd),
            address(registry),
            address(entitlements),
            address(pool),
            address(treasury)
        );
        
        // Configure roles
        cron.grantRole(cron.FACTORY_ROLE(), address(factory));
        weave.grantRole(weave.FACTORY_ROLE(), address(factory));
        fiber.grantRole(fiber.FACTORY_ROLE(), address(factory));
        dye.grantRole(dye.MINTER_ROLE(), address(factory));
        
        vm.stopBroadcast();
        
        // Log addresses
        console.log("Factory:", address(factory));
        console.log("Pool:", address(pool));
    }
}
```

### Deployment Steps
1. Deploy to testnet first
2. Verify all contracts
3. Configure roles and permissions
4. Run integration tests on testnet
5. Deploy to mainnet with multisig
6. Transfer ownership to multisig

### Post-Deployment
```bash
# Verify contracts
forge verify-contract CONTRACT_ADDRESS ContractName

# Check deployment
cast call CONTRACT_ADDRESS "owner()"

# Grant roles
cast send CONTRACT_ADDRESS "grantRole(bytes32,address)" ROLE ADDRESS
```

## Best Practices Checklist

### Before Development
- [ ] Review TDD.md for complete specifications
- [ ] Set up development environment
- [ ] Configure linting and formatting

### During Development
- [ ] Use custom errors
- [ ] Pack structs efficiently
- [ ] Implement access control
- [ ] Add comprehensive events
- [ ] Write tests alongside code

### Before Deployment
- [ ] Run full test suite
- [ ] Check gas usage
- [ ] Run security analysis
- [ ] Review with team
- [ ] Prepare deployment scripts

### After Deployment
- [ ] Verify all contracts
- [ ] Set up monitoring
- [ ] Document addresses
- [ ] Transfer to multisig
- [ ] Monitor first transactions

---

*This development guide should be used in conjunction with TDD.md for complete implementation details.*