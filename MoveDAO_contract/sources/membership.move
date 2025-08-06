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

    public fun initialize(account: &signer) {
        initialize_with_min_stake(account, 1) // Default to 10 APT
    }

    public fun initialize_with_min_stake(account: &signer, min_stake_to_join: u64) {
        let addr = signer::address_of(account);
        if (!exists<MemberList>(addr)) {
            let member_list = MemberList {
                members: simple_map::new(),
                total_members: 0,
            };

            let config = MembershipConfig {
                min_stake_to_join,
            };

            move_to(account, member_list);
            move_to(account, config);
        } else {
            abort errors::member_exists()
        }
    }

    public entry fun join(account: &signer, dao_addr: address) acquires MemberList, MembershipConfig {
        let addr = signer::address_of(account);
        let member_list = borrow_global_mut<MemberList>(dao_addr);
        
        errors::require_not_exists(!simple_map::contains_key(&member_list.members, &addr), errors::already_member());
        
        let config = borrow_global<MembershipConfig>(dao_addr);
        let stake_amount = staking::get_staked_balance(addr);
        assert!(stake_amount >= config.min_stake_to_join, errors::min_stake_required());
        
        simple_map::add(&mut member_list.members, addr, Member {
            joined_at: timestamp::now_seconds(),
        });
        
        // Add overflow protection for member count
        assert!(member_list.total_members < 18446744073709551615u64, errors::invalid_amount());
        member_list.total_members = member_list.total_members + 1;
        
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
        
        // Check if member is in the list
        let is_in_list = simple_map::contains_key(&borrow_global<MemberList>(dao_addr).members, &member);
        if (!is_in_list) return false;
        
        // Verify member still meets minimum stake requirement (prevents membership gaming)
        let config = borrow_global<MembershipConfig>(dao_addr);
        let current_stake = staking::get_staked_balance(member);
        current_stake >= config.min_stake_to_join
    }

    #[view]
    public fun get_voting_power(_dao_addr: address, member: address): u64 {
        staking::get_staked_balance(member)
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
        let current_stake = staking::get_staked_balance(member);
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

    // View function to get current minimum stake requirement
    #[view]
    public fun get_min_stake(dao_addr: address): u64 acquires MembershipConfig {
        borrow_global<MembershipConfig>(dao_addr).min_stake_to_join
    }
}