# Weave Ecosystem on Tapestry Blockchain

**Version**: 2.0  
**Date**: August 13, 2025  
**Status**: Design Complete, Ready for Implementation

## Executive Summary

Weave is an autobiographical journaling app on the Tapestry L2 blockchain that transforms user text into comic-style visual stories (FIBERs). The platform operates on a break-even model with a unique token economy where expired user entitlements become the platform's commercial inventory.

### Key Innovation
**Expired WEAVEs are not waste - they're the product.** The platform monetizes user procrastination by reselling expired entitlements to advertisers and vendors.

## Token Architecture

### Core Tokens

#### 1. CRON (Time-Wrapped Bundle)
- **Structure**: Wraps (WEAVE + DYE + [USDC/hUSDC])
- **Purpose**: 24-hour time-limited creation opportunity
- **Distribution**: 1 CRON every 6 hours per user (4 daily max)
- **Expiry**: Returns WEAVE and DYE to pools after 24 hours

#### 2. WEAVE (Creation Token)
- **Type**: Soulbound ERC-721
- **Purpose**: Represents the right to create one FIBER
- **Lifecycle**: Pool → Wrapped in CRON → Spun to user → Burned for FIBER
- **Supply**: Fixed at Users × 4 per day

#### 3. FIBER (Final Output)
- **Type**: ERC-721 NFT
- **Purpose**: The completed comic-style journal entry
- **Creation**: Minted when WEAVE burns successfully
- **Metadata**: IPFS link, creation details, sponsor info

#### 4. DYE (Computational Units)
- **Type**: ERC-20
- **Purpose**: Standardized units of computation
- **Amount**: Fixed per operation (e.g., 2500 for standard FIBER)
- **Value**: Fluctuates with technology improvements

#### 5. hUSDC (USD Hole)
- **Type**: ERC-20
- **Purpose**: Tracks actual USD costs/deficit
- **Minted**: When FIBER created (actual OpenAI cost)
- **Burned**: When revenue received

## Core Mechanics

### Entitlement System
```
Every 6 hours:
1. User can claim 1 CRON (contains WEAVE + DYE)
2. User has 24 hours to "spin" the CRON
3. Spinning creates soulbound WEAVE and burns DYE
4. Backend processes with OpenAI
5. WEAVE burns → FIBER minted + hUSDC minted
```

### Expiry Mechanism
```
If CRON not spun within 24 hours:
1. WEAVE returns to WEAVE pool (becomes inventory)
2. DYE returns to DYE pool
3. Any USDC/hUSDC in the wrap is lost
4. Distribution fees are never refunded
```

## Economic Model

### Revenue Streams

1. **Distribution Fees** (Primary)
   - Charged on all non-entitlement CRONs
   - Non-refundable even if expired
   - Dynamically priced based on inventory levels

2. **Expired WEAVE Sales** (Secondary)
   - Expired WEAVEs become platform inventory
   - Sold to advertisers/vendors
   - Price determined by scarcity

3. **No Platform Cuts**
   - Advertisers pay subsidies directly to users
   - Vendors keep 100% of premiums (minus DYE cost)
   - Platform only charges distribution fees

### Cost Structure

1. **OpenAI Costs**
   - Tracked via DYE (computational units)
   - Actual USD cost tracked via hUSDC
   - Backend reports both metrics

2. **Break-Even Model**
   - Revenue (distribution fees + pool sales) = Costs (hUSDC minted)
   - Platform operates at zero profit
   - Efficiency improvements reduce costs over time

## Pool System

### WEAVE Pool
```
Supply: Fixed at daily entitlements
Replenishment: Expired CRONs (typically 10-15%)
Depletion: Commercial wrapping
Price: Determined by scarcity
```

### DYE Pool
```
Supply: Created as needed
Replenishment: Expired CRONs
Depletion: FIBER creation
Purpose: Resource management
```

### Inventory Economics
```
Daily Flow (10,000 users):
- 40,000 WEAVEs created (entitlements)
- 36,000 spun (90% utilization) → FIBERs
- 4,000 expire → Platform inventory
- Inventory sold to advertisers/vendors
```

## Sponsorship System

### CRON Types

#### 1. Entitlement CRON (Free)
```
Structure: WEAVE + DYE
Cost: Free to user
Sponsor: Platform
```

#### 2. Gift CRON
```
Structure: WEAVE + DYE + USDC (subsidy)
Cost: Distribution fee only
Sponsor: Friend/gifter
Result: "Gifted by" watermark
```

#### 3. Advertiser CRON
```
Structure: wWEAVE + DYE + USDC (subsidy)
Advertiser pays:
- Distribution fee
- WEAVE market price
- DYE costs
- Subsidy amount
User experience: Free or even profitable (if subsidy > market price)
```

#### 4. Vendor CRON
```
Structure: wWEAVE + DYE + hUSDC (premium)
Vendor pays:
- Distribution fee
- WEAVE market price
- DYE costs
User pays: Premium amount when spinning
Vendor receives: Premium minus DYE cost
```

## Distribution Fee Model

### Dynamic Pricing Formula
```
Distribution Fee = f(inventory_level, utilization_rate, demand)

High utilization (95%):
- Low inventory (5% expiry)
- High distribution fees ($2-5)
- Rations scarce resources

Low utilization (70%):
- High inventory (30% expiry)
- Low distribution fees ($0.10-0.25)
- Encourages commercial use
```

### Fee Components
1. **Base Fee**: Operational costs
2. **Scarcity Multiplier**: Based on inventory levels
3. **Type Multiplier**: Commercial use pays more
4. **Volume Discount**: Bulk purchases get discounts

### Self-Balancing Mechanism
```
High fees → Less wrapping → More expiries → More inventory → Lower fees
Low fees → More wrapping → Fewer expiries → Less inventory → Higher fees
```

## User Journeys

### Journey 1: Standard Entitlement
```
1. 12:00 PM - Claim CRON (free)
2. 12:05 PM - Spin CRON
3. Receive soulbound WEAVE
4. DYE burns (2500 units)
5. Backend processes with OpenAI
6. WEAVE burns → FIBER minted
7. hUSDC minted (actual cost, e.g., $0.05)
8. User owns FIBER NFT
```

### Journey 2: Expired Entitlement
```
1. Monday 6 AM - Claim CRON
2. No action taken
3. Tuesday 6 AM - CRON expires
4. WEAVE returns to pool (becomes inventory)
5. DYE returns to pool
6. Platform can sell to advertisers
```

### Journey 3: Advertiser Sponsored
```
1. Nike creates 100 sponsored CRONs
2. Nike pays: dist. fee + WEAVE + DYE + subsidy
3. User claims Nike CRON (meets criteria)
4. User spins for free
5. Creates FIBER with Nike branding
6. Nike's subsidy covers user's cost
```

### Journey 4: Vendor Premium
```
1. User sees "Studio Ghibli" style CRON
2. User pays $3 premium to spin
3. Creates premium FIBER
4. Platform keeps DYE cost ($0.10)
5. Vendor receives $2.90 profit
```

## Technical Implementation

### Smart Contracts Architecture
```
Core Contracts:
├── CRONToken.sol       // Wrapper for WEAVE + DYE
├── WEAVEToken.sol      // Soulbound creation token
├── FIBERToken.sol      // Final NFT output
├── DYEToken.sol        // Computational units
├── hUSDCToken.sol      // Cost tracking
├── SimpleCRONPool.sol  // No-fee AMM for liquidity
├── WeaveFactory.sol    // Main orchestration
├── EntitlementManager.sol // 6-hour distribution
└── DynamicFeeManager.sol  // Inventory-based pricing
```

### Backend Integration
```javascript
// Process WEAVE → FIBER
async function processWEAVE(weaveId) {
  const result = await genImage(journalText);
  
  // Report actual costs
  await contract.completeWEAVE(
    weaveId,
    success,
    dyeUsed,        // Computational units
    actualCostUSD   // Real dollar cost
  );
}
```

### Pool Management
```solidity
// Automatic inventory management
function processExpiredCRON(cronId) {
  // Return to pools for resale
  weavePool.deposit(cron.weaveId);
  dyePool.deposit(cron.dyeAmount);
  
  // No refunds on distribution fees
  delete cronTokens[cronId];
}
```

## Key Insights & Innovations

### 1. Expired Inventory Model
- **Traditional view**: Expiries are waste
- **Weave innovation**: Expiries are the product
- **Result**: Platform monetizes procrastination

### 2. Dual Token Cost Tracking
- **DYE**: Standardized computational units (stable)
- **hUSDC**: Actual USD costs (variable)
- **Benefit**: Captures efficiency improvements over time

### 3. Dynamic Distribution Fees
- **Not fixed pricing**: Responds to inventory levels
- **Market-driven**: Supply/demand determines fees
- **Self-regulating**: No manual intervention needed

### 4. No Platform Cuts
- **Distribution fees only**: Clean revenue model
- **Vendors keep premiums**: Attractive to creators
- **Advertisers pay users**: Direct subsidy model

### 5. Atomic Operations
- **No token holding**: Everything happens in transactions
- **No pre-minting**: Resources created on-demand
- **Gas efficient**: Minimal on-chain storage

## Platform Metrics & Monitoring

### Key Performance Indicators
```
Health Metrics:
├── Utilization Rate: Target 85-90%
├── Inventory Days: Target 3-5 days
├── DYE:hUSDC Ratio: Efficiency indicator
├── Distribution Fee: Market indicator
└── Net Position: Treasury - hUSDC
```

### Dashboard Example
```
Platform Status
═══════════════════════════════════════
Daily Stats:
├── Users: 10,000
├── Entitlements: 40,000
├── FIBERs Created: 36,000 (90%)
├── Expired to Inventory: 4,000 (10%)

Inventory:
├── WEAVE Pool: 4,234
├── DYE Pool: 10.5M
├── Days Coverage: 2.3

Economics:
├── Distribution Fee: $0.75 (moderate)
├── hUSDC (costs): $1,800
├── Treasury: $2,100
├── Net Position: +$300 ✅

Efficiency:
├── DYE per FIBER: 2,500
├── Cost per FIBER: $0.05 (improving)
├── Revenue per FIBER: $0.083
└── Margin: 40% (healthy)
```

## Future Optimizations

### Technology Improvements
- As AI costs decrease, DYE:hUSDC ratio improves
- Platform becomes more profitable over time
- Can lower distribution fees or add features

### Scaling Considerations
- More users = more inventory
- Network effects from vendors/advertisers
- Volume discounts for bulk purchases

### Potential Enhancements
- Secondary market for FIBERs
- Governance token for platform decisions
- Cross-chain expansion
- Advanced AI models for premium FIBERs

## Conclusion

The Weave ecosystem represents a novel approach to sustainable blockchain applications. By treating expired entitlements as inventory rather than waste, the platform creates a self-balancing economy that benefits all participants:

- **Users**: Free creative tools with optional upgrades
- **Platform**: Sustainable revenue without taking cuts
- **Advertisers**: Direct access to engaged users
- **Vendors**: Platform for premium services
- **Ecosystem**: Transparent, on-chain economics

The key innovation is recognizing that in a time-based entitlement system, **expiry is not a bug - it's the feature that powers the entire economy**.

---

*This document represents the complete design as of August 13, 2025. Implementation should follow the patterns and principles outlined above.*