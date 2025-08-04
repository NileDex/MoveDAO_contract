# 🏗️ MoveDAO Creator Guide

*Your comprehensive guide to creating and managing DAOs on the MoveDAO platform*

## 🎯 **Overview**

As a DAO creator, you have the power to build thriving decentralized communities with governance, token launches, and reward systems. This guide covers everything from initial setup to advanced management features.

## 📋 **Table of Contents**

1. [Creating Your DAO](#-creating-your-dao)
2. [Administrative Management](#️-administrative-management)
3. [Council Configuration](#-council-configuration)
4. [Treasury Management](#-treasury-management)
5. [Governance Setup](#️-governance-setup)
6. [Reward System Configuration](#-reward-system-configuration)
7. [Launchpad Creation](#-launchpad-creation)
8. [Member Management](#-member-management)
9. [Security & Monitoring](#️-security--monitoring)
10. [Advanced Operations](#-advanced-operations)

---

## 🏛️ **Creating Your DAO**

### **Initial DAO Creation**
```move
// Function: dao_core::create_dao()
dao_core::create_dao(
    account: &signer,
    name: string::String,                    // DAO name (3-100 chars)
    description: string::String,             // Description (10-2000 chars)
    logo: vector<u8>,                       // Logo image data (max 1MB)
    background: vector<u8>,                 // Background image (max 5MB)
    initial_council: vector<address>,       // Initial council members
    _min_quorum_percent: u64,              // Minimum quorum (currently unused)
    min_voting_period: u64,                // Minimum voting period (seconds)
    max_voting_period: u64                 // Maximum voting period (seconds)
)
```

### **Pre-Creation Checklist**
- [ ] **Prepare DAO Identity**
  - Unique name (3-100 characters)
  - Compelling description (10-2000 characters)
  - Professional logo (under 1MB)
  - Background image (under 5MB)

- [ ] **Council Setup**
  - Select initial council members (1-100 addresses)
  - Ensure no duplicate addresses
  - Verify all addresses are valid
  - Plan council governance structure

- [ ] **Governance Parameters**
  - Minimum voting period (≥1 hour, ≤30 days)
  - Maximum voting period (≥1 hour, ≤30 days)
  - Consider community size and engagement

- [ ] **Technical Requirements**
  - Sufficient APT for gas fees
  - Aptos wallet setup
  - Contract deployment access

### **What Happens During Creation**
1. **Input Validation**: All parameters are thoroughly validated
2. **Module Initialization**: All DAO modules are set up
3. **Admin Setup**: Creator becomes super admin
4. **Council Creation**: Initial council is established
5. **Treasury Creation**: Secure treasury is initialized
6. **Governance Setup**: Proposal system is configured
7. **Staking System**: Token staking mechanism is enabled
8. **Rewards Configuration**: Default reward system is activated
9. **Event Emission**: DAO creation is logged on-chain

### **Post-Creation Verification**
```move
// Verify DAO was created successfully
dao_core::get_dao_info(dao_addr: address): (String, String, vector<u8>, vector<u8>, u64)
```

---

## 🛡️ **Administrative Management**

### **Admin Role Hierarchy**
- **Super Admin (255)**: Full system control, cannot be removed
- **Standard Admin (100)**: Most administrative functions
- **Temporary Admin (50)**: Limited time access with expiration

### **Adding Administrators**
```move
// Function: admin::add_admin()
admin::add_admin(
    admin_account: &signer,
    dao_addr: address,
    new_admin: address,
    role: u8,           // Role level (50, 100, or 255)
    expires_at: u64     // Expiration timestamp (0 for permanent)
)
```

### **Admin Management Best Practices**
- **Principle of Least Privilege**: Grant minimum necessary permissions
- **Temporary Access**: Use expiration dates for temporary admins
- **Regular Audits**: Review admin list periodically
- **Succession Planning**: Ensure multiple super admins
- **Documentation**: Keep records of admin changes

### **Removing Administrators**
```move
// Function: admin::remove_admin()
admin::remove_admin(
    admin_account: &signer,
    dao_addr: address,
    target_admin: address
)
```

**Removal restrictions:**
- Cannot remove super admins
- Must maintain minimum super admin count
- Only higher-role admins can remove lower-role admins

---

## 👥 **Council Configuration**

### **Council Management**
The council serves as a governing body with special privileges and oversight responsibilities.

### **Adding Council Members**
```move
// Function: council::add_member()
council::add_member(
    admin: &signer,
    dao_addr: address,
    new_member: address
)
```

### **Council Responsibilities**
- **Proposal Oversight**: Review and validate proposals
- **Emergency Actions**: Handle urgent DAO matters
- **Parameter Updates**: Modify DAO configuration
- **Member Moderation**: Manage community standards
- **Treasury Oversight**: Monitor fund usage

### **Council Size Management**
- **Minimum Size**: 1 member (enforced)
- **Maximum Size**: 100 members (recommended: 5-15)
- **Odd Numbers**: Recommended to avoid tie votes
- **Diversity**: Include varied perspectives and expertise

### **Removing Council Members**
```move
// Function: council::remove_member()
council::remove_member(
    admin: &signer,
    dao_addr: address,
    member_to_remove: address
)
```

---

## 💰 **Treasury Management**

### **Treasury Overview**
The DAO treasury is a secure, isolated fund storage system with reentrancy protection and multi-signature requirements.

### **Depositing to Treasury**
```move
// Function: treasury::deposit_to_object()
treasury::deposit_to_object(
    account: &signer,
    treasury_obj: Object<Treasury>,
    amount: u64
)
```

### **Withdrawing from Treasury**
```move
// Function: treasury::withdraw_from_object()
treasury::withdraw_from_object(
    account: &signer,
    dao_addr: address,
    treasury_obj: Object<Treasury>,
    amount: u64
)
```

**Withdrawal requirements:**
- Must be a DAO admin
- Sufficient treasury balance
- Reentrancy protection active
- All security checks passed

### **Treasury Security Features**
- **Reentrancy Protection**: Prevents recursive attacks
- **Access Control**: Admin-only withdrawals
- **Balance Validation**: Automatic balance checks
- **Event Logging**: All transactions recorded
- **Object Isolation**: Treasury stored in separate object

### **Treasury Best Practices**
- **Regular Monitoring**: Track balance and transactions
- **Budget Planning**: Allocate funds for operations and rewards
- **Emergency Reserves**: Maintain funds for unexpected needs
- **Transparent Reporting**: Share treasury status with community
- **Multi-Signature**: Consider additional approval layers

---

## 🗳️ **Governance Setup**

### **Proposal System Configuration**
The governance system allows democratic decision-making with weighted voting based on staking.

### **Managing Proposal Lifecycle**

#### **Starting Voting Periods**
```move
// Function: proposal::start_voting()
proposal::start_voting(
    admin: &signer,
    dao_addr: address,
    proposal_id: u64
)
```

#### **Finalizing Proposals**
```move
// Function: proposal::finalize_proposal()
proposal::finalize_proposal(
    admin: &signer,
    dao_addr: address,
    proposal_id: u64
)
```

#### **Executing Passed Proposals**
```move
// Function: proposal::execute_proposal()
proposal::execute_proposal(
    admin: &signer,
    dao_addr: address,
    proposal_id: u64
)
```

### **Governance Parameters**
- **Voting Periods**: Set appropriate timeframes for community participation
- **Quorum Requirements**: Ensure sufficient participation for legitimacy
- **Execution Windows**: Allow time for implementation after passing
- **Proposal Requirements**: Set stakes/requirements for proposal creation

### **Governance Best Practices**
- **Clear Guidelines**: Establish proposal formatting standards
- **Community Education**: Help members understand voting process
- **Regular Reviews**: Assess governance effectiveness
- **Feedback Loops**: Incorporate community suggestions
- **Transparency**: Share voting results and reasoning

---

## 🎁 **Reward System Configuration**

### **Reward Types Available**
1. **Voting Rewards**: Incentivize governance participation
2. **Proposal Creation Rewards**: Encourage community engagement
3. **Staking Rewards**: Provide passive income for token holders
4. **Successful Proposal Rewards**: Bonus for quality proposals

### **Configuring Reward Rates**
```move
// Function: rewards::update_reward_config()
rewards::update_reward_config(
    admin: &signer,
    dao_addr: address,
    voting_reward_per_vote: u64,        // Tokens per vote cast
    proposal_creation_reward: u64,      // Tokens per proposal created
    successful_proposal_reward: u64,    // Bonus for passed proposals
    staking_yield_rate: u64,           // Annual percentage (e.g., 500 = 5%)
    staking_distribution_interval: u64  // Seconds between distributions
)
```

### **Reward System Management**

#### **Enabling/Disabling Rewards**
```move
// Function: rewards::toggle_rewards()
rewards::toggle_rewards(
    admin: &signer,
    dao_addr: address,
    enabled: bool
)
```

#### **Distributing Staking Rewards**
```move
// Function: rewards::distribute_staking_rewards()
rewards::distribute_staking_rewards(
    admin: &signer,
    dao_addr: address,
    stakers: vector<address>,
    staked_amounts: vector<u64>
)
```

### **Reward Economics Planning**
- **Sustainability**: Ensure treasury can support reward rates
- **Inflation Control**: Balance rewards with token economics
- **Participation Incentives**: Set rates to encourage engagement
- **Long-term Viability**: Plan for changing community needs
- **Regular Reviews**: Adjust rates based on performance

---

## 🚀 **Launchpad Creation**

### **Creating a DAO Launchpad**
```move
// Function: dao_core::create_dao_launchpad()
dao_core::create_dao_launchpad(
    admin: &signer,
    dao_addr: address,
    project_name: string::String,           // Token project name
    token_name: string::String,             // Token symbol/name
    total_supply: u64,                      // Total token supply
    price_per_token: u64,                   // Price in micro-APT
    presale_allocation_percent: u64,        // % for presale (0-100)
    team_allocation_percent: u64,           // % for team (0-100)
    vesting_cliff_months: u64,             // Cliff period in months
    vesting_duration_months: u64,          // Total vesting duration
    kyc_required: bool                      // Whether KYC is required
)
```

### **Launchpad Timeline Management**
```move
// Function: launchpad::update_timeline()
launchpad::update_timeline(
    admin: &signer,
    dao_addr: address,
    whitelist_start: u64,      // Whitelist phase start
    presale_start: u64,        // Presale phase start
    public_sale_start: u64,    // Public sale start
    sale_end: u64,             // Sale end time
    vesting_start: u64         // Vesting start time
)
```

### **Whitelist Management**

#### **Batch Whitelist Addition**
```move
// Function: launchpad::add_to_whitelist()
launchpad::add_to_whitelist(
    admin: &signer,
    dao_addr: address,
    participants: vector<address>,    // Max 50 per batch
    tiers: vector<u8>,               // Tier levels (1-4)
    max_allocations: vector<u64>     // Max tokens per participant
)
```

#### **Single Participant Addition**
```move
// Function: launchpad::add_single_to_whitelist()
launchpad::add_single_to_whitelist(
    admin: &signer,
    dao_addr: address,
    participant: address,
    tier: u8,                // 1=Bronze, 2=Silver, 3=Gold, 4=Platinum
    max_allocation: u64
)
```

### **Launchpad Phase Management**
```move
// Function: launchpad::advance_phase()
launchpad::advance_phase(
    admin: &signer,
    dao_addr: address
)
```

**Phase progression:**
1. **Setup**: Configuration and preparation
2. **Whitelist**: Registration and tier assignment
3. **Presale**: Exclusive access for whitelisted users
4. **Public Sale**: Open access for all DAO members
5. **Ended**: Sale completed, vesting begins

### **Emergency Controls**
```move
// Emergency pause
launchpad::emergency_pause(admin: &signer, dao_addr: address)

// Resume operations
launchpad::emergency_resume(admin: &signer, dao_addr: address)
```

### **Vesting Schedule Management**
```move
// Function: launchpad::create_vesting_schedule()
launchpad::create_vesting_schedule(
    admin: &signer,
    dao_addr: address,
    beneficiary: address,
    total_amount: u64,
    cliff_duration: u64,
    vesting_duration: u64
)
```

---

## 👥 **Member Management**

### **Monitoring Membership**
```move
// View active members
membership::is_member(dao_addr: address, user_addr: address): bool

// Check member count
membership::get_member_count(dao_addr: address): u64
```

### **Member Moderation**
```move
// Function: membership::remove_inactive_member()
membership::remove_inactive_member(
    admin: &signer,
    dao_addr: address,
    inactive_member: address
)
```

### **Member Engagement Strategies**
- **Onboarding Programs**: Help new members understand the DAO
- **Education Resources**: Provide governance and platform guides
- **Incentive Alignment**: Use rewards to encourage participation
- **Community Building**: Foster interaction and collaboration
- **Regular Communication**: Keep members informed of developments

---

## 🛡️ **Security & Monitoring**

### **Security Features**
Your DAO includes enterprise-grade security measures:

- **Reentrancy Protection**: Treasury operations are protected
- **Integer Overflow Protection**: Safe math operations throughout
- **Access Control**: Multi-layer permission validation
- **Input Validation**: Comprehensive bounds checking
- **Timestamp Security**: Protection against time manipulation
- **Gas Optimization**: Batch limits prevent gas exhaustion

### **Monitoring Capabilities**

#### **Key Events to Monitor**
- **DAOCreated**: DAO initialization
- **AdminChanged**: Administrative changes
- **MemberJoined/Left**: Membership changes
- **ProposalCreated**: New governance proposals
- **VoteCast**: Voting activity
- **RewardClaimed**: Reward distributions
- **TokensPurchased**: Launchpad activity
- **TreasuryDeposit/Withdrawal**: Financial transactions

#### **Health Metrics**
- Member growth rate
- Voting participation
- Proposal success rate
- Treasury balance trends
- Reward distribution efficiency
- Staking participation

### **Security Best Practices**
- **Regular Audits**: Review admin permissions and activities
- **Backup Plans**: Ensure multiple super admins
- **Incident Response**: Prepare for emergency situations
- **Community Communication**: Keep members informed of security updates
- **Continuous Monitoring**: Watch for unusual activities

---

## 🔧 **Advanced Operations**

### **System Maintenance**

#### **Staking Registry Repair**
```move
// Function: staking::repair_staker_sync()
staking::repair_staker_sync(
    admin: &signer,
    dao_addr: address,
    staker: address,
    correct_amount: u64
)
```

#### **Reward System Maintenance**
- Monitor reward distribution intervals
- Adjust rates based on treasury health
- Handle edge cases in reward calculations
- Ensure system sustainability

### **Data Migration**
If you need to upgrade or migrate:
- Export member lists and balances
- Document governance history
- Plan transition timeline
- Communicate with community
- Test migration thoroughly

### **Integration Opportunities**
- **External Platforms**: Connect with other DeFi protocols
- **Analytics Tools**: Integrate monitoring dashboards
- **Communication Bots**: Automate community updates
- **Mobile Apps**: Build user-friendly interfaces
- **Cross-Chain Bridges**: Expand to other blockchains

### **Scaling Considerations**
- **Performance Optimization**: Monitor gas usage patterns
- **Community Growth**: Plan for increased membership
- **Feature Expansion**: Add new capabilities gradually
- **Infrastructure**: Ensure robust hosting and monitoring
- **Documentation**: Keep guides updated

---

## 📊 **Success Metrics**

### **Key Performance Indicators**
- **Member Growth**: Track membership acquisition and retention
- **Governance Health**: Monitor proposal creation and voting rates
- **Financial Health**: Track treasury balance and reward sustainability
- **Community Engagement**: Measure participation across all features
- **Platform Usage**: Monitor feature adoption and usage patterns

### **Reporting Tools**
```move
// Essential view functions for monitoring
dao_core::get_dao_info(dao_addr: address)
membership::get_member_count(dao_addr: address)
treasury::get_balance_from_object(treasury_obj: Object<Treasury>)
proposal::get_proposal_count(dao_addr: address)
staking::get_total_staked(dao_addr: address)
```

---

## 🆘 **Troubleshooting**

### **Common Issues and Solutions**

#### **Low Participation**
- Review reward rates and incentives
- Improve communication and education
- Simplify participation processes
- Engage with community directly

#### **Treasury Depletion**
- Adjust reward rates to sustainable levels
- Encourage community contributions
- Implement treasury management policies
- Plan fundraising initiatives

#### **Governance Gridlock**
- Review quorum requirements
- Improve proposal quality guidelines
- Facilitate community discussion
- Consider governance parameter adjustments

#### **Technical Issues**
- Monitor error logs and events
- Test all functions regularly
- Keep documentation updated
- Maintain emergency contacts

### **Emergency Procedures**
1. **Identify Issue**: Quickly assess the situation
2. **Communicate**: Inform community immediately
3. **Implement Fix**: Use appropriate admin functions
4. **Monitor**: Watch for resolution and side effects
5. **Document**: Record incident and resolution
6. **Review**: Improve processes to prevent recurrence

---

## 🎯 **Quick Reference**

### **Essential Creator Functions**
| Action | Function | Access Level |
|--------|----------|-------------|
| Create DAO | `dao_core::create_dao()` | Anyone |
| Add Admin | `admin::add_admin()` | Super Admin |
| Manage Council | `council::add_member()` | Admin |
| Treasury Withdrawal | `treasury::withdraw_from_object()` | Admin |
| Start Voting | `proposal::start_voting()` | Admin |
| Configure Rewards | `rewards::update_reward_config()` | Admin |
| Create Launchpad | `dao_core::create_dao_launchpad()` | Admin |
| Manage Whitelist | `launchpad::add_to_whitelist()` | Admin |
| Emergency Pause | `launchpad::emergency_pause()` | Admin |

### **Security Checklist**
- [ ] Multiple super admins configured
- [ ] Regular admin permission audits
- [ ] Treasury balance monitoring
- [ ] Community communication channels
- [ ] Emergency response procedures
- [ ] Backup and recovery plans
- [ ] Regular security reviews

---

## 🌟 **Best Practices Summary**

### **Governance**
- Set clear, achievable goals
- Encourage diverse participation
- Maintain transparent processes
- Regular community engagement
- Continuous improvement mindset

### **Financial Management**
- Conservative treasury management
- Sustainable reward economics
- Regular financial reporting
- Emergency fund maintenance
- Community input on major decisions

### **Community Building**
- Welcome new members warmly
- Provide educational resources
- Recognize contributions
- Foster inclusive environment
- Celebrate community achievements

### **Technical Operations**
- Monitor system health regularly
- Keep documentation current
- Test changes thoroughly
- Plan for growth and scaling
- Maintain security vigilance

---

**Congratulations on creating your DAO! 🎉**

*You're now equipped to build and manage a thriving decentralized community. Remember, successful DAOs are built on trust, transparency, and community engagement.*

**Build the future, one DAO at a time! 🚀**