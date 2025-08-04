# 👥 MoveDAO User Guide

*Your complete guide to participating in MoveDAO communities*

## 🚀 **Getting Started**

Welcome to MoveDAO! As a user, you can participate in decentralized governance, earn rewards, stake tokens, and participate in exclusive token launches. This guide will walk you through everything you can do within the MoveDAO ecosystem.

## 📋 **Table of Contents**

1. [Joining a DAO](#-joining-a-dao)
2. [Staking & Voting Power](#-staking--voting-power)
3. [Governance Participation](#️-governance-participation)
4. [Earning & Claiming Rewards](#-earning--claiming-rewards)
5. [Launchpad Participation](#-launchpad-participation)
6. [Treasury Interactions](#-treasury-interactions)
7. [Advanced Features](#-advanced-features)

---

## 🏛️ **Joining a DAO**

### **How to Join**
```move
// Function: membership::join()
membership::join(account: &signer, dao_addr: address)
```

**What you need:**
- An Aptos wallet with APT tokens
- The DAO's contract address
- Minimum staking requirement (varies by DAO)

**Steps:**
1. Ensure you have sufficient APT tokens
2. Call the `join` function with the DAO address
3. You'll automatically become a member if requirements are met

**Benefits of membership:**
- ✅ Voting rights on proposals
- ✅ Ability to create proposals
- ✅ Eligibility for rewards
- ✅ Access to exclusive launchpads
- ✅ Community governance participation

### **Leaving a DAO**
```move
// Function: membership::leave()
membership::leave(account: &signer, dao_addr: address)
```

**Important notes:**
- You must unstake all tokens first
- Any pending rewards will be forfeited
- You lose all voting rights immediately

---

## 💰 **Staking & Voting Power**

### **Staking Tokens**
```move
// Function: staking::stake()
staking::stake(account: &signer, dao_addr: address, amount: u64)
```

**How staking works:**
- Stake APT tokens to gain voting power
- 1 staked APT = 1 vote weight
- Staked tokens are locked but earn rewards
- Higher stake = more influence in governance

**Benefits of staking:**
- 🗳️ **Voting Power**: Influence DAO decisions
- 💎 **Staking Rewards**: Earn passive income
- 🎯 **Proposal Rights**: Create governance proposals
- 🚀 **Launchpad Access**: Priority in token sales

### **Unstaking Tokens**
```move
// Function: staking::unstake()
staking::unstake(account: &signer, dao_addr: address, amount: u64)
```

**Unstaking rules:**
- Can unstake partial amounts
- Reduces your voting power proportionally
- May have cooldown periods (DAO-specific)
- Affects your reward eligibility

### **Viewing Your Stake**
```move
// View function: staking::get_staked_balance()
staking::get_staked_balance(user_addr: address): u64
```

---

## 🗳️ **Governance Participation**

### **Viewing Proposals**
```move
// View function: proposal::get_proposal()
proposal::get_proposal(dao_addr: address, proposal_id: u64): Proposal
```

**Proposal information includes:**
- Title and description
- Current vote counts (Yes/No/Abstain)
- Voting period start/end times
- Execution window
- Current status

### **Voting on Proposals**
```move
// Function: proposal::cast_vote()
proposal::cast_vote(
    account: &signer,
    dao_addr: address,
    proposal_id: u64,
    vote_type: VoteType,    // Yes, No, or Abstain
    weight: u64             // Amount of voting power to use
)
```

**Voting rules:**
- Must be a DAO member
- Can only vote during active voting period
- Vote weight limited by your staking power
- Cannot change vote once cast
- Earn rewards for participating

**Vote types:**
- **Yes**: Support the proposal
- **No**: Oppose the proposal  
- **Abstain**: Neutral participation (still earns rewards)

### **Creating Proposals**
```move
// Function: proposal::create_proposal()
proposal::create_proposal(
    account: &signer,
    dao_addr: address,
    title: string::String,
    description: string::String,
    execution_window: u64
)
```

**Requirements to create proposals:**
- Must be a DAO member
- Must have minimum staking amount
- Title: 3-100 characters
- Description: 10-2000 characters
- Reasonable execution window

**Proposal lifecycle:**
1. **Draft**: Proposal created, not yet active
2. **Active**: Voting period open
3. **Passed/Rejected**: Based on vote results
4. **Executed**: Successful proposals implemented
5. **Cancelled**: Can be cancelled by creator or admin

---

## 🎁 **Earning & Claiming Rewards**

### **Types of Rewards**

#### **Voting Rewards**
- Earn tokens for participating in governance
- Reward per vote (configured by DAO)
- Applies to Yes, No, and Abstain votes

#### **Proposal Creation Rewards**
- Bonus for creating proposals
- Encourages community engagement
- Fixed amount per proposal

#### **Staking Rewards**
- Passive income from staked tokens
- Annual percentage yield (APY)
- Distributed periodically

#### **Successful Proposal Rewards**
- Bonus for creating proposals that pass
- Incentivizes quality proposals
- Higher reward than creation bonus

### **Claiming Rewards**
```move
// Function: dao_core::claim_rewards()
dao_core::claim_rewards(account: &signer, dao_addr: address)
```

**How claiming works:**
- Automatically calculates all pending rewards
- Transfers tokens from DAO treasury
- Updates your reward history
- Emits claim event for tracking

**Security features:**
- Multi-layer validation prevents fraud
- Reentrancy protection
- Membership verification
- Treasury balance checks

### **Viewing Rewards**
```move
// View function: rewards::get_total_claimable()
rewards::get_total_claimable(dao_addr: address, user_addr: address): u64
```

---

## 🚀 **Launchpad Participation**

### **Understanding Launch Phases**

#### **Phase 1: Whitelist**
- Registration period for eligible participants
- Tier-based allocation system
- KYC verification (if required)

#### **Phase 2: Presale**
- Exclusive access for whitelisted users
- Discounted token prices
- Limited allocation per tier

#### **Phase 3: Public Sale**
- Open to all DAO members
- Standard pricing
- First-come, first-served

### **Participating in Token Sales**
```move
// Function: launchpad::purchase_tokens()
launchpad::purchase_tokens(
    account: &signer,
    dao_addr: address,
    amount: u64    // Amount of tokens to purchase
)
```

**Purchase requirements:**
- Must be DAO member
- Sale phase must be active
- Sufficient APT balance
- Within allocation limits (if whitelisted)

**Tier system benefits:**
- **Bronze**: Basic allocation, 20% immediate unlock
- **Silver**: Higher allocation, 30% immediate unlock
- **Gold**: Premium allocation, 40% immediate unlock
- **Platinum**: Maximum allocation, 50% immediate unlock

### **Vesting & Token Claims**
```move
// Function: launchpad::claim_vested_tokens()
launchpad::claim_vested_tokens(account: &signer, dao_addr: address)
```

**Vesting schedule:**
- Tokens unlock gradually over time
- Cliff period before first unlock
- Linear vesting after cliff
- Claim anytime after vesting starts

---

## 🏦 **Treasury Interactions**

### **Contributing to Treasury**
```move
// Function: treasury::deposit_to_object()
treasury::deposit_to_object(
    account: &signer,
    treasury_obj: Object<Treasury>,
    amount: u64
)
```

**Anyone can contribute:**
- Support DAO operations
- Increase reward pool
- Show community commitment
- Transparent on-chain tracking

### **Viewing Treasury Balance**
```move
// View function: treasury::get_balance_from_object()
treasury::get_balance_from_object(treasury_obj: Object<Treasury>): u64
```

**Treasury transparency:**
- All transactions are public
- Real-time balance tracking
- Withdrawal requires admin approval
- Used for rewards and operations

---

## 🔧 **Advanced Features**

### **Emergency Actions**

#### **If Launchpad is Paused**
- Wait for admin to resume
- Monitor announcements
- Funds remain safe in contract

#### **If You Need to Leave Urgently**
1. Unstake all tokens
2. Claim all pending rewards
3. Leave the DAO
4. Funds returned to your wallet

### **Troubleshooting Common Issues**

#### **"Not a member" Error**
- Ensure you've joined the DAO
- Check if you were removed for inactivity
- Verify you're using correct DAO address

#### **"Insufficient stake" Error**
- Stake more tokens to meet minimum
- Check current staking requirements
- Ensure tokens aren't already staked elsewhere

#### **"Voting period ended" Error**
- Proposal voting has closed
- Check proposal status and timing
- Wait for next proposal to participate

#### **"Nothing to claim" Error**
- No pending rewards available
- Participate in governance to earn rewards
- Check if rewards system is enabled

### **Best Practices**

#### **Security**
- Always verify DAO contract addresses
- Keep your private keys secure
- Double-check transaction details
- Monitor your staking and rewards

#### **Participation**
- Stay informed about proposals
- Vote on issues you understand
- Engage with the community
- Provide constructive feedback

#### **Rewards Optimization**
- Stake consistently for better rewards
- Participate in all votes
- Create quality proposals
- Claim rewards regularly

---

## 📊 **Monitoring Your Activity**

### **Events to Track**
- **MemberJoined**: When you join a DAO
- **TokensStaked**: Your staking activities
- **VoteCast**: Your voting participation
- **RewardClaimed**: Reward distributions
- **TokensPurchased**: Launchpad purchases

### **Useful View Functions**
```move
// Check membership status
membership::is_member(dao_addr: address, user_addr: address): bool

// View voting power
staking::get_staked_balance(user_addr: address): u64

// Check proposal details
proposal::get_proposal(dao_addr: address, proposal_id: u64): Proposal

// View claimable rewards
rewards::get_total_claimable(dao_addr: address, user_addr: address): u64
```

---

## 🆘 **Getting Help**

### **Common Resources**
- DAO community forums
- Official documentation
- Discord/Telegram channels
- GitHub repository

### **Technical Support**
- Check transaction status on Aptos Explorer
- Verify contract addresses
- Review error messages carefully
- Contact DAO administrators if needed

---

## 🎯 **Quick Reference**

### **Essential Functions for Users**
| Action | Function | Requirements |
|--------|----------|-------------|
| Join DAO | `membership::join()` | APT tokens, meet minimums |
| Stake tokens | `staking::stake()` | DAO membership, APT tokens |
| Vote on proposal | `proposal::cast_vote()` | Staked tokens, active proposal |
| Claim rewards | `dao_core::claim_rewards()` | Pending rewards available |
| Buy tokens | `launchpad::purchase_tokens()` | Active sale, sufficient APT |
| Claim vested | `launchpad::claim_vested_tokens()` | Vesting period started |

### **View Functions (No gas cost)**
| Information | Function |
|------------|----------|
| Membership status | `membership::is_member()` |
| Staking balance | `staking::get_staked_balance()` |
| Proposal details | `proposal::get_proposal()` |
| Pending rewards | `rewards::get_total_claimable()` |
| Treasury balance | `treasury::get_balance_from_object()` |

---

**Welcome to the future of decentralized governance! 🌟**

*Happy participating in your DAO community!*