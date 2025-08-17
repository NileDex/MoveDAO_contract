// Platform Statistics - provides aggregated statistics across all DAOs for platform overview
module dao_addr::platform_stats {
    use std::vector;
    use dao_addr::membership;
    use dao_addr::proposal;
    use dao_addr::errors;

    // Global registry to track all DAOs
    struct PlatformRegistry has key {
        dao_addresses: vector<address>,
        total_daos_created: u64,
        global_admin: address,  // Platform admin who can manage the registry
    }

    // Platform-wide statistics cache (updated periodically for performance)
    struct PlatformStats has key {
        total_daos: u64,
        active_proposals: u64,
        total_votes_cast: u64,
        total_community_members: u64,
        last_updated: u64,
    }

    // Individual DAO statistics for aggregation
    struct DAOStats has store, copy, drop {
        dao_address: address,
        active_proposals: u64,
        total_proposals: u64,
        total_members: u64,
        total_votes: u64,
    }

    // Initialize the platform registry (should be called once when deploying)
    public entry fun initialize_platform(admin: &signer) {
        let admin_addr = std::signer::address_of(admin);
        assert!(!exists<PlatformRegistry>(admin_addr), errors::admin_list_exists());
        
        let registry = PlatformRegistry {
            dao_addresses: vector::empty(),
            total_daos_created: 0,
            global_admin: admin_addr,
        };

        let stats = PlatformStats {
            total_daos: 0,
            active_proposals: 0,
            total_votes_cast: 0,
            total_community_members: 0,
            last_updated: aptos_framework::timestamp::now_seconds(),
        };

        move_to(admin, registry);
        move_to(admin, stats);
    }

    // Register a new DAO when it's created
    public entry fun register_dao(platform_admin: &signer, dao_address: address) acquires PlatformRegistry {
        let admin_addr = std::signer::address_of(platform_admin);
        assert!(exists<PlatformRegistry>(admin_addr), errors::not_found());
        
        let registry = borrow_global_mut<PlatformRegistry>(admin_addr);
        assert!(admin_addr == registry.global_admin, errors::not_admin());
        
        // Check if DAO is already registered
        if (!vector::contains(&registry.dao_addresses, &dao_address)) {
            vector::push_back(&mut registry.dao_addresses, dao_address);
            registry.total_daos_created = registry.total_daos_created + 1;
        };
    }

    // Update platform statistics by aggregating data from all registered DAOs
    public entry fun update_platform_stats(platform_admin: &signer) acquires PlatformRegistry, PlatformStats {
        let admin_addr = std::signer::address_of(platform_admin);
        assert!(exists<PlatformRegistry>(admin_addr), errors::not_found());
        assert!(exists<PlatformStats>(admin_addr), errors::not_found());
        
        let registry = borrow_global<PlatformRegistry>(admin_addr);
        assert!(admin_addr == registry.global_admin, errors::not_admin());
        
        let stats = borrow_global_mut<PlatformStats>(admin_addr);
        
        // Reset counters
        let total_active_proposals = 0;
        let total_votes_cast = 0;
        let total_members = 0;
        
        // Aggregate statistics from all registered DAOs
        let i = 0;
        let len = vector::length(&registry.dao_addresses);
        while (i < len) {
            let dao_addr = *vector::borrow(&registry.dao_addresses, i);
            
            // Get DAO statistics if the DAO still exists
            if (exists_dao(dao_addr)) {
                let dao_stats = get_dao_stats(dao_addr);
                total_active_proposals = total_active_proposals + dao_stats.active_proposals;
                total_votes_cast = total_votes_cast + dao_stats.total_votes;
                total_members = total_members + dao_stats.total_members;
            };
            
            i = i + 1;
        };
        
        // Update platform statistics
        stats.total_daos = registry.total_daos_created;
        stats.active_proposals = total_active_proposals;
        stats.total_votes_cast = total_votes_cast;
        stats.total_community_members = total_members;
        stats.last_updated = aptos_framework::timestamp::now_seconds();
    }

    // View function to get current platform statistics
    #[view]
    public fun get_platform_overview(platform_admin: address): (u64, u64, u64, u64, u64) acquires PlatformStats {
        assert!(exists<PlatformStats>(platform_admin), errors::not_found());
        let stats = borrow_global<PlatformStats>(platform_admin);
        (
            stats.total_daos,
            stats.active_proposals,
            stats.total_votes_cast,
            stats.total_community_members,
            stats.last_updated
        )
    }

    // View function to get all registered DAO addresses
    #[view]
    public fun get_registered_daos(platform_admin: address): vector<address> acquires PlatformRegistry {
        assert!(exists<PlatformRegistry>(platform_admin), errors::not_found());
        let registry = borrow_global<PlatformRegistry>(platform_admin);
        registry.dao_addresses
    }

    // View function to get total number of registered DAOs
    #[view]
    public fun get_total_daos(platform_admin: address): u64 acquires PlatformRegistry {
        if (!exists<PlatformRegistry>(platform_admin)) return 0;
        let registry = borrow_global<PlatformRegistry>(platform_admin);
        registry.total_daos_created
    }

    // Get detailed statistics for a specific DAO
    #[view]
    public fun get_dao_detailed_stats(dao_address: address): (u64, u64, u64, u64, u64) {
        if (!exists_dao(dao_address)) return (0, 0, 0, 0, 0);
        
        let total_proposals = proposal::get_proposals_count(dao_address);
        let active_proposals = get_active_proposal_count(dao_address);
        let total_members = membership::total_members(dao_address);
        let total_voting_power = membership::total_voting_power(dao_address);
        let total_votes = get_total_votes_count(dao_address);
        
        (total_proposals, active_proposals, total_members, total_voting_power, total_votes)
    }

    // Helper function to check if a DAO exists (has DAOInfo)
    fun exists_dao(dao_address: address): bool {
        // Check if the DAO has the core DAOInfo resource
        dao_addr::dao_core::dao_exists(dao_address)
    }

    // Helper function to get DAO statistics for aggregation
    fun get_dao_stats(dao_address: address): DAOStats {
        let active_proposals = get_active_proposal_count(dao_address);
        let total_proposals = proposal::get_proposals_count(dao_address);
        let total_members = membership::total_members(dao_address);
        let total_votes = get_total_votes_count(dao_address);
        
        DAOStats {
            dao_address,
            active_proposals,
            total_proposals,
            total_members,
            total_votes,
        }
    }

    // Helper function to count active proposals in a DAO
    fun get_active_proposal_count(dao_address: address): u64 {
        if (!proposal::has_proposals(dao_address)) return 0;
        
        let total_proposals = proposal::get_proposals_count(dao_address);
        let active_count = 0;
        let i = 0;
        
        while (i < total_proposals) {
            let (_, _, _, _, status, _, _, _, _, _, _, _, _, _, _, _) = proposal::get_proposal_details(dao_address, i);
            // Status 1 = Active, Status 2 = Voting
            if (status == 1 || status == 2) {
                active_count = active_count + 1;
            };
            i = i + 1;
        };
        
        active_count
    }

    // Helper function to count total votes cast in a DAO
    fun get_total_votes_count(dao_address: address): u64 {
        if (!proposal::has_proposals(dao_address)) return 0;
        
        let total_proposals = proposal::get_proposals_count(dao_address);
        let total_votes = 0;
        let i = 0;
        
        while (i < total_proposals) {
            let vote_count = proposal::get_proposal_vote_count(dao_address, i);
            total_votes = total_votes + vote_count;
            i = i + 1;
        };
        
        total_votes
    }

    // Batch function to get overview for multiple DAOs
    #[view]
    public fun get_multiple_dao_stats(dao_addresses: vector<address>): vector<DAOStats> {
        let stats = vector::empty<DAOStats>();
        let i = 0;
        let len = vector::length(&dao_addresses);
        
        while (i < len) {
            let dao_addr = *vector::borrow(&dao_addresses, i);
            if (exists_dao(dao_addr)) {
                let dao_stats = get_dao_stats(dao_addr);
                vector::push_back(&mut stats, dao_stats);
            };
            i = i + 1;
        };
        
        stats
    }

    // Real-time aggregation function (more expensive but always current)
    #[view]
    public fun get_realtime_platform_stats(platform_admin: address): (u64, u64, u64, u64) acquires PlatformRegistry {
        if (!exists<PlatformRegistry>(platform_admin)) return (0, 0, 0, 0);
        
        let registry = borrow_global<PlatformRegistry>(platform_admin);
        let total_active_proposals = 0;
        let total_votes_cast = 0;
        let total_members = 0;
        
        let i = 0;
        let len = vector::length(&registry.dao_addresses);
        while (i < len) {
            let dao_addr = *vector::borrow(&registry.dao_addresses, i);
            if (exists_dao(dao_addr)) {
                let dao_stats = get_dao_stats(dao_addr);
                total_active_proposals = total_active_proposals + dao_stats.active_proposals;
                total_votes_cast = total_votes_cast + dao_stats.total_votes;
                total_members = total_members + dao_stats.total_members;
            };
            i = i + 1;
        };
        
        (registry.total_daos_created, total_active_proposals, total_votes_cast, total_members)
    }
}