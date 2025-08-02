module dao_addr::membership {
    use std::signer;
    use std::simple_map::{Self, SimpleMap};
    use std::event;
    use aptos_framework::timestamp;
    use dao_addr::staking;

    const EMEMBER_EXISTS: u64 = 1;
    const ENOT_MEMBER: u64 = 2;
    const EALREADY_MEMBER: u64 = 3;
    const EMIN_STAKE_REQUIRED: u64 = 4;
    const MIN_STAKE_TO_JOIN: u64 = 100;

    struct Member has store, copy, drop {
        joined_at: u64,
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

    public fun initialize(account: &signer) {
        let addr = signer::address_of(account);
        if (!exists<MemberList>(addr)) {
            let member_list = MemberList {
                members: simple_map::new(),
                total_members: 0,
            };

            move_to(account, member_list);
        } else {
            abort EMEMBER_EXISTS
        }
    }

    public entry fun join(account: &signer, dao_addr: address) acquires MemberList {
        let addr = signer::address_of(account);
        let member_list = borrow_global_mut<MemberList>(dao_addr);
        
        assert!(!simple_map::contains_key(&member_list.members, &addr), EALREADY_MEMBER);
        
        let stake_amount = staking::get_staked_balance(addr);
        assert!(stake_amount >= MIN_STAKE_TO_JOIN, EMIN_STAKE_REQUIRED);
        
        simple_map::add(&mut member_list.members, addr, Member {
            joined_at: timestamp::now_seconds(),
        });
        
        member_list.total_members = member_list.total_members + 1;
        
        event::emit(MemberJoined {
            member: addr
        });
    }

    public entry fun leave(account: &signer, dao_addr: address) acquires MemberList {
        let addr = signer::address_of(account);
        let member_list = borrow_global_mut<MemberList>(dao_addr);
        
        assert!(simple_map::contains_key(&member_list.members, &addr), ENOT_MEMBER);
        simple_map::remove(&mut member_list.members, &addr);
        
        member_list.total_members = member_list.total_members - 1;
        
        event::emit(MemberLeft { member: addr });
    }

    #[view]
    public fun is_member(dao_addr: address, member: address): bool acquires MemberList {
        if (!exists<MemberList>(dao_addr)) return false;
        simple_map::contains_key(&borrow_global<MemberList>(dao_addr).members, &member)
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
}