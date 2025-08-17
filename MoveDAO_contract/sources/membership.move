// Membership system - manages who can join the DAO based on staking requirements and tracks member status
module dao_addr::membership {
    use std::signer;
    use std::simple_map::{Self, SimpleMap};
    use std::event;
    use aptos_framework::timestamp;
    use dao_addr::admin;
    use dao_addr::staking;
    use dao_addr::errors;

    struct Member has store, copy, drop {
        joined_at: u64,
    }

    struct MembershipConfig has key {
        min_stake_to_join: u64,
        min_stake_to_propose: u64,  // Minimum stake required to create proposals
    }

    struct MemberList has key {
        members: SimpleMap<address, Member>,
        total_members: u64,
    }

    #[event]
    struct MemberJoined has drop, store {
        member: address
    }

    #[event]
    struct MemberLeft has drop, store {
        member: address
    }

    #[event]
    struct MinStakeUpdated has drop, store {
        old_min_stake: u64,
        new_min_stake: u64,
        updated_by: address
    }

    #[event]
    struct MinProposalStakeUpdated has drop, store {
        old_min_proposal_stake: u64,
        new_min_proposal_stake: u64,
        updated_by: address
    }

    public fun initialize(account: &signer) {
        initialize_with_min_stake(account, 1) // Default to 10 APT
    }

    public fun initialize_with_min_stake(account: &signer, min_stake_to_join: u64) {
        initialize_with_stake_requirements(account, min_stake_to_join, min_stake_to_join) // Default: same as join stake, admin can customize later
    }

    public fun initialize_with_stake_requirements(account: &signer, min_stake_to_join: u64, min_stake_to_propose: u64) {
        let addr = signer::address_of(account);
        if (!exists<MemberList>(addr)) {
            let member_list = MemberList {
                members: simple_map::new(),
                total_members: 0,
            };

            let config = MembershipConfig {
                min_stake_to_join,
                min_stake_to_propose,
            };

            move_to(account, member_list);
            move_to(account, config);
        } else {
            abort errors::member_exists()
        }
    }

    /// Join the DAO as a member
    /// 
    /// MINIMUM STAKE ENFORCEMENT:
    /// - Users must have staked at least the minimum amount before joining
    /// - Minimum stake is set when DAO is created (e.g., 10 MOVE tokens for Gorilla Moverz)
    /// - If user hasn't staked enough tokens, join() will fail with min_stake_required error
    /// - This prevents people from joining without commitment to the DAO
    /// 
    /// PROCESS:
    /// 1. Check if user is already a member (prevent duplicate joins)
    /// 2. Get the DAO's minimum stake requirement from config
    /// 3. Check user's current staked balance
    /// 4. If staked balance >= minimum requirement -> Allow join
    /// 5. If staked balance < minimum requirement -> Reject with error
    /// 6. Add user to member list and emit join event
    /// 
    /// EXAMPLE FOR GORILLA MOVERZ:
    /// - Minimum stake: 10 MOVE tokens
    /// - User stakes 15 MOVE -> Can join (15 >= 10)
    /// - User stakes 5 MOVE -> Cannot join (5 < 10)
    /// - User stakes 0 MOVE -> Cannot join (0 < 10)
    public entry fun join(account: &signer, dao_addr: address) acquires MemberList, MembershipConfig {
        let addr = signer::address_of(account);
        let member_list = borrow_global_mut<MemberList>(dao_addr);
        
        // Prevent duplicate membership
        errors::require_not_exists(!simple_map::contains_key(&member_list.members, &addr), errors::already_member());
        
        // Get the DAO's minimum stake requirement
        let config = borrow_global<MembershipConfig>(dao_addr);
        // Check user's current staked balance in THIS DAO (not global)
        let stake_amount = staking::get_staker_amount(dao_addr, addr);
        // Enforce minimum stake requirement - this is the key validation!
        assert!(stake_amount >= config.min_stake_to_join, errors::min_stake_required());
        
        // User meets requirements - add to member list
        simple_map::add(&mut member_list.members, addr, Member {
            joined_at: timestamp::now_seconds(),
        });
        
        // Add overflow protection for member count
        assert!(member_list.total_members < 18446744073709551615u64, errors::invalid_amount());
        member_list.total_members = member_list.total_members + 1;
        
        // Emit event for tracking
        event::emit(MemberJoined {
            member: addr
        });
    }

    public entry fun leave(account: &signer, dao_addr: address) acquires MemberList {
        let addr = signer::address_of(account);
        let member_list = borrow_global_mut<MemberList>(dao_addr);
        
        errors::require_member(simple_map::contains_key(&member_list.members, &addr));
        
        // Allow voluntary leaving regardless of stake (users can choose to leave)
        // The is_member function will handle continuous validation of membership privileges
        
        simple_map::remove(&mut member_list.members, &addr);
        member_list.total_members = member_list.total_members - 1;
        
        event::emit(MemberLeft { member: addr });
    }

    #[view]
    public fun is_member(dao_addr: address, member: address): bool acquires MemberList, MembershipConfig {
        if (!exists<MemberList>(dao_addr)) return false;
        if (!exists<MembershipConfig>(dao_addr)) return false;
        
        // Admin bypass: Admins are always considered members regardless of stake or membership status
        if (admin::is_admin(dao_addr, member)) return true;
        
        // Check if member is in the list (has joined the DAO)
        let is_in_list = simple_map::contains_key(&borrow_global<MemberList>(dao_addr).members, &member);
        if (!is_in_list) return false;
        
        // CRITICAL: Verify member still meets minimum stake requirement (prevents membership gaming)
        // This is the key validation that enforces minimum stake for proposal creation
        let config = borrow_global<MembershipConfig>(dao_addr);
        let current_stake = staking::get_staker_amount(dao_addr, member);
        current_stake >= config.min_stake_to_join
    }

    #[view]
    public fun get_voting_power(dao_addr: address, member: address): u64 acquires MembershipConfig {
        // Admin bypass: Give admins voting power equal to their stake, or minimum proposal stake if they have no stake
        if (admin::is_admin(dao_addr, member)) {
            let staked_amount = staking::get_staker_amount(dao_addr, member);
            if (staked_amount > 0) {
                return staked_amount
            } else {
                // If admin has no stake, give them voting power equal to minimum proposal stake requirement
                if (exists<MembershipConfig>(dao_addr)) {
                    return borrow_global<MembershipConfig>(dao_addr).min_stake_to_propose
                } else {
                    return 1  // Fallback minimum voting power
                }
            }
        };
        staking::get_staker_amount(dao_addr, member)
    }

    #[view]
    public fun total_members(dao_addr: address): u64 acquires MemberList {
        borrow_global<MemberList>(dao_addr).total_members
    }

    #[view]
    public fun total_voting_power(dao_addr: address): u64 {
        staking::get_total_staked(dao_addr)
    }

    public entry fun update_voting_power(_account: &signer) {
        // No-op since voting power is dynamically calculated
    }

    // Administrative function to remove members who no longer meet stake requirements
    public entry fun remove_inactive_member(
        admin: &signer, 
        dao_addr: address, 
        member: address
    ) acquires MemberList, MembershipConfig {
        let admin_addr = signer::address_of(admin);
        assert!(admin::is_admin(dao_addr, admin_addr), errors::not_admin());
        
        let member_list = borrow_global_mut<MemberList>(dao_addr);
        let config = borrow_global<MembershipConfig>(dao_addr);
        
        // Verify member exists in list
        assert!(simple_map::contains_key(&member_list.members, &member), errors::not_member());
        
        // Verify member no longer meets minimum stake requirement
        let current_stake = staking::get_staker_amount(dao_addr, member);
        assert!(current_stake < config.min_stake_to_join, errors::min_stake_required());
        
        // Remove the member
        simple_map::remove(&mut member_list.members, &member);
        member_list.total_members = member_list.total_members - 1;
        
        event::emit(MemberLeft { member });
    }

    // Administrative function to update minimum stake requirement
    public entry fun update_min_stake(
        admin: &signer,
        dao_addr: address,
        new_min_stake: u64
    ) acquires MembershipConfig {
        let admin_addr = signer::address_of(admin);
        assert!(admin::is_admin(dao_addr, admin_addr), errors::not_admin());
        
        // Validate new minimum stake (reasonable bounds)
        assert!(new_min_stake > 0, errors::invalid_amount());
        assert!(new_min_stake <= 10000, errors::invalid_amount());
        
        let config = borrow_global_mut<MembershipConfig>(dao_addr);
        let old_min_stake = config.min_stake_to_join;
        config.min_stake_to_join = new_min_stake;
        
        event::emit(MinStakeUpdated {
            old_min_stake,
            new_min_stake,
            updated_by: admin_addr
        });
    }

    // Administrative function to update minimum proposal creation stake requirement
    public entry fun update_min_proposal_stake(
        admin: &signer,
        dao_addr: address,
        new_min_proposal_stake: u64
    ) acquires MembershipConfig {
        let admin_addr = signer::address_of(admin);
        assert!(admin::is_admin(dao_addr, admin_addr), errors::not_admin());
        
        // Validate new minimum proposal stake (reasonable bounds)
        assert!(new_min_proposal_stake > 0, errors::invalid_amount());
        assert!(new_min_proposal_stake <= 100000, errors::invalid_amount()); // Max 1M tokens
        
        let config = borrow_global_mut<MembershipConfig>(dao_addr);
        
        // Ensure proposal stake is at least as much as join stake to maintain hierarchy
        assert!(new_min_proposal_stake >= config.min_stake_to_join, errors::invalid_amount());
        
        let old_min_proposal_stake = config.min_stake_to_propose;
        config.min_stake_to_propose = new_min_proposal_stake;
        
        event::emit(MinProposalStakeUpdated {
            old_min_proposal_stake,
            new_min_proposal_stake,
            updated_by: admin_addr
        });
    }

    // Convenient function for admins to set proposal stake as a multiplier of join stake
    public entry fun set_proposal_stake_multiplier(
        admin: &signer,
        dao_addr: address,
        multiplier: u64
    ) acquires MembershipConfig {
        let admin_addr = signer::address_of(admin);
        assert!(admin::is_admin(dao_addr, admin_addr), errors::not_admin());
        
        // Validate multiplier (1x to 100x)
        assert!(multiplier >= 1, errors::invalid_amount());
        assert!(multiplier <= 100, errors::invalid_amount());
        
        let config = borrow_global<MembershipConfig>(dao_addr);
        let new_min_proposal_stake = config.min_stake_to_join * multiplier;
        
        // Use the existing update function to ensure all validations
        update_min_proposal_stake(admin, dao_addr, new_min_proposal_stake);
    }

    // View function to get current minimum stake requirement
    #[view]
    public fun get_min_stake(dao_addr: address): u64 acquires MembershipConfig {
        borrow_global<MembershipConfig>(dao_addr).min_stake_to_join
    }

    // View function to get current minimum proposal stake requirement
    #[view]
    public fun get_min_proposal_stake(dao_addr: address): u64 acquires MembershipConfig {
        borrow_global<MembershipConfig>(dao_addr).min_stake_to_propose
    }

    // View function to get the current proposal stake multiplier
    #[view]
    public fun get_proposal_stake_multiplier(dao_addr: address): u64 acquires MembershipConfig {
        let config = borrow_global<MembershipConfig>(dao_addr);
        if (config.min_stake_to_join == 0) return 1;
        config.min_stake_to_propose / config.min_stake_to_join
    }

    // Check if a member can create proposals based on stake requirements
    #[view]
    public fun can_create_proposal(dao_addr: address, member: address): bool acquires MemberList, MembershipConfig {
        if (!exists<MemberList>(dao_addr)) return false;
        if (!exists<MembershipConfig>(dao_addr)) return false;
        
        // Admin bypass: Admins can always create proposals regardless of stake requirements
        if (admin::is_admin(dao_addr, member)) return true;
        
        // Must be a member first
        if (!is_member(dao_addr, member)) return false;
        
        // Check if member meets proposal creation stake requirement
        let config = borrow_global<MembershipConfig>(dao_addr);
        let current_stake = staking::get_staker_amount(dao_addr, member);
        current_stake >= config.min_stake_to_propose
    }
}