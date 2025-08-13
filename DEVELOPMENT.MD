# Weave Ecosystem Development Guide

**Version**: 1.0  
**Date**: August 13, 2025  
**Purpose**: Technical development guide for implementing the Weave ecosystem smart contracts

## Table of Contents
1. [Architecture Decisions](#architecture-decisions)
2. [Technology Stack](#technology-stack)
3. [Contract Architecture](#contract-architecture)
4. [Modern Solidity Patterns](#modern-solidity-patterns)
5. [Security Best Practices](#security-best-practices)
6. [Gas Optimization Strategies](#gas-optimization-strategies)
7. [Development Workflow](#development-workflow)
8. [Testing Strategy](#testing-strategy)
9. [Deployment Guide](#deployment-guide)
10. [Future-Proofing](#future-proofing)

## Architecture Decisions

### Why NOT Diamond Standard (EIP-2535)

While Diamond Standard offers unlimited contract size and modular upgrades, we've decided **against** using it for Weave because:

1. **Unnecessary Complexity**: Our contracts don't approach the 24KB limit
2. **Audit Difficulty**: Diamond patterns are harder to audit and verify
3. **Debugging Challenges**: Complex delegate call patterns make debugging difficult
4. **Overkill**: We don't need the extreme modularity Diamond provides

### Our Approach: Hybrid Architecture

We use a combination of patterns optimized for different needs:

```
┌─────────────────────────────────────────────────┐
│              WeaveRegistry                       │
│         (Central registry for discovery)         │
└─────────────────┬───────────────────────────────┘
                  │
    ┌─────────────┼─────────────┬──────────────┐
    ▼             ▼             ▼              ▼
┌─────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐
│ Tokens  │  │ Factory  │  │   Pool   │  │Treasury │
│Immutable│  │   UUPS   │  │Immutable │  │  UUPS   │
└─────────┘  └──────────┘  └──────────┘  └─────────┘
```

#### Immutable Contracts
- **Tokens**: DYE, hUSDC (Simple ERC-20s don't need upgrades)
- **Core NFTs**: CRON (ERC-721), WEAVE (ERC-1155), FIBER (ERC-1155)
- **Pool**: SimpleCRONPool (AMM logic is well-tested)

#### UUPS Upgradeable
- **Factory**: Main orchestration (may need feature additions)
- **Treasury**: Revenue management (may need new revenue streams)
- **FeeManager**: Dynamic pricing (may need algorithm updates)

#### Modular Components
- **EntitlementModule**: Handles 6-hour distributions
- **AdvertiserModule**: Manages subsidies
- **VendorModule**: Handles premium transformations

## Technology Stack

### Core Technologies
- **Blockchain**: Tapestry L2 (Ethereum-compatible)
- **Language**: Solidity 0.8.20+
- **Framework**: Foundry
- **Libraries**: OpenZeppelin Contracts 5.0
- **Testing**: Forge (Foundry's testing framework)

### Development Tools
```bash
# Required installations
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Project setup
forge init --no-commit
forge install OpenZeppelin/openzeppelin-contracts
forge install OpenZeppelin/openzeppelin-contracts-upgradeable
```

### Configuration
```toml
# foundry.toml
[profile.default]
src = "contracts"
out = "out"
libs = ["lib"]
test = "test"
cache = true

optimizer = true
optimizer_runs = 200
solc_version = "0.8.20"

# Enable new features
evm_version = "shanghai"  # For PUSH0 opcode
via_ir = true            # For better optimization

[profile.production]
optimizer = true
optimizer_runs = 10000   # Optimize for many runs
```

## Contract Architecture

### Registry Pattern

The registry serves as the single source of truth for contract addresses:

```solidity
contract WeaveRegistry {
    // Core token addresses (immutable after setting)
    address public immutable CRON;    // ERC-721 NFT
    address public immutable WEAVE;   // ERC-1155 Semi-fungible
    address public immutable FIBER;   // ERC-1155 Collections
    address public immutable DYE;     // ERC-20 Fungible
    address public immutable hUSDC;   // ERC-20 Deficit tracker
    
    // Upgradeable components
    address public factory;
    address public treasury;
    address public feeManager;
    
    // Modules
    address public entitlementModule;
    address public advertiserModule;
    address public vendorModule;
    address public providerRegistry;  // Multi-provider support
    
    // Events
    event FactoryUpdated(address indexed old, address indexed new);
    
    // Only owner can update upgradeable components
    function updateFactory(address _factory) external onlyOwner {
        emit FactoryUpdated(factory, _factory);
        factory = _factory;
    }
}
```

### UUPS Proxy Pattern

For upgradeable contracts, we use UUPS (Universal Upgradeable Proxy Standard):

```solidity
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract WeaveFactoryV1 is UUPSUpgradeable, OwnableUpgradeable {
    // State variables with gaps for future additions
    uint256 public constant VERSION = 1;
    
    // ... contract logic ...
    
    // Reserve storage slots for future versions
    uint256[50] private __gap;
    
    function _authorizeUpgrade(address newImplementation) 
        internal 
        override 
        onlyOwner 
    {}
}
```

### Modular Design

Each module handles a specific concern:

```solidity
// Entitlement Module
contract EntitlementModule {
    IWeaveRegistry public immutable registry;
    uint256 public constant INTERVAL = 6 hours;
    
    mapping(address => uint256) public lastClaim;
    
    function claimEntitlement() external {
        require(block.timestamp >= lastClaim[msg.sender] + INTERVAL);
        lastClaim[msg.sender] = block.timestamp;
        
        IWeaveFactory(registry.factory()).createEntitlementCRON(msg.sender);
    }
}
```

## Modern Solidity Patterns

### Custom Errors (Gas Efficient)
```solidity
// Instead of require strings
error InsufficientBalance(uint256 requested, uint256 available);
error CRONExpired(uint256 cronId, uint256 expiredAt);
error Unauthorized(address caller, bytes32 requiredRole);

// Usage
if (balance < amount) {
    revert InsufficientBalance(amount, balance);
}
```

### User-Defined Value Types
```solidity
// Type safety without overhead
type CronId is uint256;
type DyeAmount is uint256;
type UserId is address;

// Prevents mixing up parameters
function processCRON(CronId cronId, DyeAmount dye) external {
    // Can't accidentally pass DyeAmount where CronId expected
}
```

### Named Mappings
```solidity
// Clear, self-documenting code
mapping(address user => mapping(CronId => CronData)) public userCrons;
mapping(UserId user => EntitlementData) public entitlements;
mapping(address advertiser => CampaignData) public campaigns;
```

### Transient Storage (EIP-1153)
```solidity
// Gas-efficient temporary storage (cleared after transaction)
contract OptimizedReentrancyGuard {
    // Slot 0 for reentrancy flag
    modifier nonReentrant() {
        assembly {
            if tload(0) { revert(0, 0) }
            tstore(0, 1)
        }
        _;
        assembly {
            tstore(0, 0)
        }
    }
}
```

### Struct Packing
```solidity
// Optimized struct for ERC-721 CRON metadata
struct CronData {
    uint128 providerId;   // Slot 1 - Which provider can process
    uint128 dyeAmount;    // Slot 1 - Computational units
    uint64 expiryTime;    // Slot 2 - 24-hour expiry
    uint64 monetaryValue; // Slot 2 - USDC/hUSDC amount
    uint32 complexity;    // Slot 2 - Complexity multiplier
    address sponsor;      // Slot 3 - Who paid for this
    bool isSubsidy;       // Slot 3 - Subsidy vs premium
    // Total: 3 slots, optimized for NFT use
}
```

## Security Best Practices

### Access Control
```solidity
contract SecureContract {
    using AccessControl for *;
    
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");
    bytes32 public constant BACKEND_ROLE = keccak256("BACKEND");
    
    modifier onlyOperator() {
        if (!hasRole(OPERATOR_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender, OPERATOR_ROLE);
        }
        _;
    }
}
```

### Circuit Breaker Pattern
```solidity
contract EmergencyStop {
    bool private stopped;
    
    modifier stopInEmergency() {
        if (stopped) revert("Emergency stop");
        _;
    }
    
    modifier onlyInEmergency() {
        if (!stopped) revert("Not in emergency");
        _;
    }
    
    function emergencyStop() external onlyOwner {
        stopped = true;
        emit EmergencyStopped(msg.sender);
    }
}
```

### Time-Locked Administration
```solidity
contract TimeLocked {
    uint256 constant TIMELOCK = 48 hours;
    
    struct PendingAction {
        address target;
        bytes data;
        uint256 executeAfter;
    }
    
    mapping(bytes32 => PendingAction) public pendingActions;
    
    function proposeAction(address target, bytes calldata data) 
        external 
        onlyOwner 
        returns (bytes32 actionId) 
    {
        actionId = keccak256(abi.encode(target, data, block.timestamp));
        pendingActions[actionId] = PendingAction({
            target: target,
            data: data,
            executeAfter: block.timestamp + TIMELOCK
        });
    }
    
    function executeAction(bytes32 actionId) external onlyOwner {
        PendingAction memory action = pendingActions[actionId];
        require(block.timestamp >= action.executeAfter, "Still locked");
        
        delete pendingActions[actionId];
        (bool success,) = action.target.call(action.data);
        require(success, "Execution failed");
    }
}
```

### Pull Payment Pattern
```solidity
contract PullPayment {
    mapping(address => uint256) private payments;
    
    function asyncTransfer(address dest, uint256 amount) internal {
        payments[dest] += amount;
    }
    
    function withdrawPayments(address payable payee) external {
        uint256 payment = payments[payee];
        payments[payee] = 0;
        payee.sendValue(payment);
    }
}
```

## Gas Optimization Strategies

### Batch Operations
```solidity
function batchProcessExpiredCRONs(CronId[] calldata cronIds) external {
    unchecked {  // Safe: we control array iteration
        for (uint256 i; i < cronIds.length; ++i) {
            if (_isExpired(cronIds[i])) {
                _processExpired(cronIds[i]);
            }
        }
    }
}
```

### Storage vs Memory
```solidity
// Expensive: multiple storage reads
function badPattern() external view returns (uint256) {
    return userBalance[msg.sender] + userBalance[msg.sender] * 2;
}

// Cheaper: single storage read
function goodPattern() external view returns (uint256) {
    uint256 balance = userBalance[msg.sender];  // Cache in memory
    return balance + balance * 2;
}
```

### Events for Data Storage
```solidity
// Store non-critical data in events instead of storage
event CronMetadata(uint256 indexed cronId, string ipfsHash, bytes metadata);

function createCRON() external {
    uint256 cronId = nextCronId++;
    // Only store essential data in storage
    crons[cronId] = CronData({
        owner: msg.sender,
        expiryTime: block.timestamp + 24 hours
    });
    
    // Emit detailed metadata in event (much cheaper)
    emit CronMetadata(cronId, ipfsHash, additionalData);
}
```

### Minimal Proxy Pattern
```solidity
import "@openzeppelin/contracts/proxy/Clones.sol";

contract UserVaultFactory {
    address public immutable vaultImplementation;
    
    constructor() {
        vaultImplementation = address(new UserVault());
    }
    
    function createVault() external returns (address vault) {
        // Deploy minimal proxy (much cheaper than full contract)
        vault = Clones.clone(vaultImplementation);
        UserVault(vault).initialize(msg.sender);
    }
}
```

## Development Workflow

### Project Structure
```
tapestry/
├── contracts/
│   ├── tokens/
│   │   ├── CRONToken.sol       // ERC-721 NFT
│   │   ├── WEAVEToken.sol      // ERC-1155 Semi-fungible
│   │   ├── FIBERToken.sol      // ERC-1155 Collections
│   │   ├── DYEToken.sol        // ERC-20 Computational units
│   │   └── hUSDCToken.sol      // ERC-20 Deficit tracker
│   ├── core/
│   │   ├── WeaveRegistry.sol
│   │   ├── WeaveFactory.sol
│   │   └── Treasury.sol
│   ├── modules/
│   │   ├── EntitlementModule.sol
│   │   ├── AdvertiserModule.sol
│   │   ├── VendorModule.sol
│   │   └── ProviderRegistry.sol  // Multi-provider management
│   ├── pools/
│   │   └── SimpleCRONPool.sol
│   └── interfaces/
│       └── IWeaveEcosystem.sol
├── test/
│   ├── unit/
│   ├── integration/
│   ├── invariant/
│   └── utils/
│       └── TestHelpers.sol
├── script/
│   ├── Deploy.s.sol
│   └── Upgrade.s.sol
└── foundry.toml
```

### Development Commands
```bash
# Build contracts
forge build

# Run tests
forge test

# Run specific test
forge test --match-test testCRONExpiry

# Gas report
forge test --gas-report

# Coverage
forge coverage

# Format code
forge fmt

# Security check
slither .
```

## Testing Strategy

### Unit Testing
```solidity
contract DYETokenTest is Test {
    DYEToken dye;
    address alice = makeAddr("alice");
    
    function setUp() public {
        dye = new DYEToken();
    }
    
    function test_MintDYE() public {
        uint256 amount = 1000;
        dye.mint(alice, amount);
        assertEq(dye.balanceOf(alice), amount);
    }
    
    function testFuzz_MintDYE(uint256 amount) public {
        vm.assume(amount < type(uint256).max);
        dye.mint(alice, amount);
        assertEq(dye.balanceOf(alice), amount);
    }
}
```

### Integration Testing
```solidity
contract FullFlowTest is Test {
    WeaveEcosystem ecosystem;
    
    function test_EntitlementToFIBER() public {
        // Setup
        address user = makeAddr("user");
        vm.startPrank(user);
        
        // Claim entitlement
        ecosystem.claimEntitlement();
        
        // Spin CRON
        ecosystem.spinCRON(1);
        
        // Simulate backend
        vm.stopPrank();
        vm.prank(backend);
        ecosystem.completeWEAVE(1, true, 50000, "ipfs://");
        
        // Verify
        assertEq(ecosystem.fiberToken().ownerOf(1), user);
    }
}
```

### Invariant Testing
```solidity
contract InvariantTest is Test {
    WeaveEcosystem ecosystem;
    
    function invariant_ConservationOfValue() public {
        uint256 totalDYE = ecosystem.dyeToken().totalSupply();
        uint256 totalHUSDC = ecosystem.husdcToken().totalSupply();
        
        // DYE minted should roughly equal hUSDC minted
        assertApproxEqRel(totalDYE * ecosystem.dyeToUSDRate(), totalHUSDC, 0.1e18);
    }
    
    function invariant_NoNegativeBalances() public {
        assertTrue(address(ecosystem.treasury()).balance >= 0);
        assertTrue(ecosystem.usdcToken().balanceOf(address(ecosystem.treasury())) >= 0);
    }
}
```

## Deployment Guide

### Deployment Script
```solidity
// script/Deploy.s.sol
contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy tokens
        CRONToken cron = new CRONToken("Weave CRON", "CRON");
        WEAVEToken weave = new WEAVEToken("uri://weave/{id}");
        FIBERToken fiber = new FIBERToken("uri://fiber/{id}");
        DYEToken dye = new DYEToken();
        hUSDCToken husdc = new hUSDCToken();
        
        // Deploy registry
        WeaveRegistry registry = new WeaveRegistry(
            address(cron),
            address(weave),
            address(fiber),
            address(dye),
            address(husdc)
        );
        
        // Deploy factory (UUPS)
        WeaveFactory factoryImpl = new WeaveFactory();
        ERC1967Proxy factoryProxy = new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(factoryImpl.initialize, (address(registry)))
        );
        
        // Update registry
        registry.updateFactory(address(factoryProxy));
        
        vm.stopBroadcast();
        
        // Log addresses
        console.log("Registry:", address(registry));
        console.log("Factory:", address(factoryProxy));
    }
}
```

### Deployment Commands
```bash
# Deploy to local
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $TAPESTRY_TESTNET_RPC --broadcast --verify

# Deploy to mainnet
forge script script/Deploy.s.sol --rpc-url $TAPESTRY_MAINNET_RPC --broadcast --verify --slow
```

### Verification
```bash
# Verify on Etherscan-compatible explorer
forge verify-contract \
    --chain-id 42161 \
    --num-of-optimizations 200 \
    --compiler-version v0.8.20 \
    $CONTRACT_ADDRESS \
    contracts/tokens/DYEToken.sol:DYEToken
```

## Future-Proofing

### Account Abstraction Support (ERC-4337)
```solidity
contract AACompatible {
    // Support for smart contract wallets
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData) {
        // Validate signature and pay gas
    }
}
```

### Cross-Chain Considerations
```solidity
contract CrossChainEnabled {
    // Support for LayerZero or similar
    mapping(uint16 => bytes) public trustedRemotes;
    
    function setTrustedRemote(uint16 _chainId, bytes calldata _path) external onlyOwner {
        trustedRemotes[_chainId] = _path;
    }
}
```

### Upgrade Patterns
```solidity
contract WeaveFactoryV2 is WeaveFactoryV1 {
    // New state variables after __gap
    uint256 public newFeature;
    
    function initializeV2(uint256 _newFeature) external reinitializer(2) {
        newFeature = _newFeature;
    }
    
    // Override version
    function version() public pure override returns (uint256) {
        return 2;
    }
}
```

### Migration Strategy
```solidity
contract MigrationHelper {
    function migrateUsers(
        address[] calldata users,
        uint256[] calldata balances
    ) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            newContract.setBalance(users[i], balances[i]);
        }
    }
}
```

## Best Practices Checklist

### Before Development
- [ ] Define clear contract interfaces
- [ ] Plan upgrade strategy
- [ ] Design gas-efficient data structures
- [ ] Consider account abstraction

### During Development
- [ ] Use custom errors instead of require strings
- [ ] Pack structs efficiently
- [ ] Cache storage variables in memory
- [ ] Use events for non-critical data
- [ ] Implement circuit breakers
- [ ] Add comprehensive natspec comments

### Before Deployment
- [ ] Run full test suite
- [ ] Check gas consumption
- [ ] Run security analysis (Slither, Mythril)
- [ ] Get code audited
- [ ] Test upgrade process
- [ ] Verify on testnet

### After Deployment
- [ ] Verify all contracts
- [ ] Set up monitoring
- [ ] Document contract addresses
- [ ] Transfer ownership to multisig
- [ ] Set up incident response plan

## Conclusion

This development guide provides a modern, secure, and gas-efficient approach to building the Weave ecosystem. By avoiding unnecessary complexity (like Diamond Standard) and embracing proven patterns (UUPS, Registry, Modular design), we create a maintainable and upgradeable system that can evolve with user needs while maintaining security and efficiency.

Remember: **Simplicity is the ultimate sophistication**. Use the simplest pattern that meets your needs.

---

*For questions or suggestions, please open an issue in the repository.*