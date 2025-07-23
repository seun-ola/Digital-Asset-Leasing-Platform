# Digital Asset Leasing Platform

A smart contract for the Stacks blockchain that enables digital asset holders to lease their tokens for revenue generation while allowing lessees to utilize assets temporarily without full acquisition.

## Overview

This platform creates a decentralized marketplace where:
- **Asset Holders** can post their digital assets for lease and earn passive income
- **Lessees** can temporarily use assets without purchasing them outright
- **Platform** facilitates secure transactions with dispute resolution mechanisms

## Key Features

### For Asset Holders
- List digital assets for lease with custom pricing
- Set minimum and maximum lease terms
- Earn revenue from multiple lease cycles
- Update pricing when assets are not actively leased
- Remove listings when no active leases exist

### For Lessees
- Browse available assets and get instant pricing quotes
- Lease assets for flexible durations
- Deposit system ensures responsible usage
- Automatic deposit return upon asset return
- Transaction history tracking

### Platform Features
- 5% service fee (configurable by admin)
- Automated expiration handling
- Dispute resolution system
- User metrics and reputation scoring
- Revenue tracking and withdrawal

## Contract Functions

### Core Operations

#### `post-asset-for-lease`
Posts a digital asset for lease with specified terms.
```clarity
(post-asset-for-lease asset-contract asset-id rate-per-block minimum-term maximum-term)
```

#### `lease-asset`
Leases an available asset for a specified duration.
```clarity
(lease-asset post-id term)
```

#### `return-asset`
Returns a leased asset and retrieves deposit.
```clarity
(return-asset post-id)
```

### Management Functions

#### `auto-return-expired`
Anyone can trigger return of expired leases.
```clarity
(auto-return-expired post-id)
```

#### `update-lease-rate`
Asset holders can update pricing when not actively leased.
```clarity
(update-lease-rate post-id new-rate-per-block)
```

#### `remove-posting`
Asset holders can remove listings when no active lease exists.
```clarity
(remove-posting post-id)
```

### Read-Only Functions

- `get-posting(post-id)` - Get lease posting details
- `get-current-lease(post-id)` - Get active lease information  
- `get-user-metrics(user)` - Get user statistics and reputation
- `get-lease-estimate(post-id, term)` - Calculate lease costs before committing
- `is-lease-expired(post-id)` - Check if a lease has expired
- `get-platform-statistics()` - View platform metrics

## Economic Model

### Pricing Structure
- **Lease Cost**: `rate-per-block × lease-duration`
- **Service Fee**: 5% of lease cost (goes to platform)
- **Deposit**: 20% of lease cost (returned when asset is returned)
- **Total Payment**: `lease-cost + deposit`


### Revenue Distribution
- **Asset Holder**: 95% of lease cost
- **Platform**: 5% service fee
- **Lessee**: Deposit returned upon asset return

## Security Features

### Deposit System
- 20% deposit required from lessees
- Automatically returned when asset is properly returned
- Can be forfeited in dispute resolution

### Access Controls
- Only asset holders can modify their postings
- Only lessees can return their leased assets
- Platform admin can resolve disputes
- Prevents self-leasing

### Validation
- Comprehensive input validation
- Ownership verification requirements
- Duration limits enforcement
- Prevents double-listing of assets

## Admin Functions

Platform administrators can:
- `set-service-fee-percentage` - Adjust platform fees (max 20%)
- `set-term-limits` - Configure minimum/maximum lease durations
- `withdraw-service-fees` - Withdraw accumulated platform revenue
- `resolve-conflict` - Handle disputes between parties

## Error Codes

- `u200` - Admin-only function
- `u201` - Item not found
- `u202` - Access denied
- `u203` - Invalid value
- `u204` - Asset already posted
- `u205` - Asset not accessible for lease
- `u206` - Lease currently in progress
- `u207` - Lease has ended
- `u208` - Insufficient funds
- `u209` - Invalid timeframe
- `u210` - Asset not controlled by caller

## Usage Example

```clarity
;; 1. Post an asset for lease
(contract-call? .asset-lease-contract post-asset-for-lease 
  .my-nft-contract 
  u123 
  u100  ;; 100 microSTX per block
  u144  ;; minimum 1 day
  u1440 ;; maximum 10 days
)

;; 2. Get a quote for leasing
(contract-call? .asset-lease-contract get-lease-estimate u1 u720) ;; 5 days

;; 3. Lease the asset
(contract-call? .asset-lease-contract lease-asset u1 u720)

;; 4. Return the asset
(contract-call? .asset-lease-contract return-asset u1)
```
