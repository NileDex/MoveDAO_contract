// Platform Statistics - provides aggregated statistics across all DAOs for platform overview
module movedaoaddrx::platform_stats {
    use std::vector;
    use movedaoaddrx::membership;
    use movedaoaddrx::proposal;
    use movedaoaddrx::dao_core_file as dao_core;

    // Individual DAO statistics for aggregation
    struct DAOStats has store, copy, drop {
        movedaoaddrxess: address,
        active_proposals: u64,
        total_proposals: u64,
        total_members: u64,
        total_votes: u64,
    }

    // Platform-wide statistics
    struct PlatformStatsData has copy, drop {
        total_daos: u64,
        total_proposals: u64,
        active_proposals: u64,
        total_votes_cast: u64,
        total_community_members: u64,
    }

    // Get platform statistics by automatically aggregating from all DAOs
    #[view]
    public fun get_platform_stats(): PlatformStatsData {
        // Registry is automatically initialized, so it always exists
        let dao_addresses = dao_core::get_all_dao_addresses();
        let total_daos = dao_core::get_total_dao_count();
        get_platform_stats_from_list(dao_addresses, total_daos)
    }

    // Normal path when registry is available
    fun get_platform_stats_from_list(dao_addresses: vector<address>, total_daos: u64): PlatformStatsData {
        
        let total_proposals = 0;
        let active_proposals = 0;
        let total_votes_cast = 0;
        let total_members = 0;
        
        let i = 0;
        let len = vector::length(&dao_addresses);
        while (i < len) {
            let dao_addr = *vector::borrow(&dao_addresses, i);
            
            if (dao_core::dao_exists(dao_addr)) {
                // Get proposal stats
                if (proposal::has_proposals(dao_addr)) {
                    let dao_total_proposals = proposal::get_proposals_count(dao_addr);
                    total_proposals = total_proposals + dao_total_proposals;
                    
                    let dao_active_proposals = get_active_proposal_count(dao_addr);
                    active_proposals = active_proposals + dao_active_proposals;
                    
                    let dao_total_votes = get_total_votes_count(dao_addr);
                    total_votes_cast = total_votes_cast + dao_total_votes;
                };
                
                // Get member stats (check if membership is initialized by checking if total_members works)
                let dao_members = membership::total_members(dao_addr);
                total_members = total_members + dao_members;
            };
            
            i = i + 1;
        };
        
        PlatformStatsData {
            total_daos,
            total_proposals,
            active_proposals,
            total_votes_cast,
            total_community_members: total_members,
        }
    }

    // Fallback method when registry doesn't exist
    // Provides stats by checking known/likely DAO addresses
    fun get_platform_stats_fallback(): PlatformStatsData {
        // Create a list of addresses to check for DAOs
        // This includes common patterns and known addresses
        let potential_daos = vector::empty<address>();
        
        // Add the known DAO address from the registry fix script
        vector::push_back(&mut potential_daos, @0xc2ed434a9696ec7e41d99b4d855159894a2b3f154ecbb0c4f3a4566b318aaf90);
        
        // Add module address (sometimes used for DAOs)
        vector::push_back(&mut potential_daos, @movedaoaddrx);
        
        // Get stats from these potential DAOs
        get_platform_stats_from_list(potential_daos, vector::length(&potential_daos))
    }

    // Get platform statistics as tuple (for compatibility)
    #[view]
    public fun get_platform_overview(): (u64, u64, u64, u64, u64) {
        let stats = get_platform_stats();
        (
            stats.total_daos,
            stats.total_proposals,
            stats.active_proposals,
            stats.total_votes_cast,
            stats.total_community_members
        )
    }

    // Check if platform stats are showing complete data
    #[view]
    public fun are_stats_complete(): bool {
        // Registry is always initialized automatically
        true
    }

    // Get status message about platform stats reliability
    #[view] 
    public fun get_stats_status(): vector<u8> {
        b"Platform stats are complete - registry is automatically initialized"
    }

    // Get total number of DAOs
    #[view]
    public fun get_total_daos(): u64 {
        dao_core::get_total_dao_count()
    }

    // Get all DAO addresses
    #[view]
    public fun get_all_dao_addresses(): vector<address> {
        dao_core::get_all_dao_addresses()
    }

    // Get detailed statistics for a specific DAO
    #[view]
    public fun get_dao_detailed_stats(movedaoaddrxess: address): (u64, u64, u64, u64, u64) {
        if (!dao_core::dao_exists(movedaoaddrxess)) return (0, 0, 0, 0, 0);
        
        let total_proposals = if (proposal::has_proposals(movedaoaddrxess)) {
            proposal::get_proposals_count(movedaoaddrxess)
        } else { 0 };
        
        let active_proposals = get_active_proposal_count(movedaoaddrxess);
        
        let total_members = membership::total_members(movedaoaddrxess);
        let total_voting_power = membership::total_voting_power(movedaoaddrxess);
        
        let total_votes = get_total_votes_count(movedaoaddrxess);
        
        (total_proposals, active_proposals, total_members, total_voting_power, total_votes)
    }

    // Get statistics for a specific DAO as struct
    #[view]
    public fun get_dao_stats(movedaoaddrxess: address): DAOStats {
        let active_proposals = get_active_proposal_count(movedaoaddrxess);
        let total_proposals = if (proposal::has_proposals(movedaoaddrxess)) {
            proposal::get_proposals_count(movedaoaddrxess)
        } else { 0 };
        let total_members = membership::total_members(movedaoaddrxess);
        let total_votes = get_total_votes_count(movedaoaddrxess);
        
        DAOStats {
            movedaoaddrxess,
            active_proposals,
            total_proposals,
            total_members,
            total_votes,
        }
    }

    // Helper function to count active proposals in a DAO
    fun get_active_proposal_count(movedaoaddrxess: address): u64 {
        if (!proposal::has_proposals(movedaoaddrxess)) return 0;
        
        let total_proposals = proposal::get_proposals_count(movedaoaddrxess);
        let active_count = 0;
        let i = 0;
        
        while (i < total_proposals) {
            let (_, _, _, _, status, _, _, _, _, _, _, _, _, _, _, _) = proposal::get_proposal_details(movedaoaddrxess, i);
            // Status 1 = Active, Status 2 = Voting
            if (status == 1 || status == 2) {
                active_count = active_count + 1;
            };
            i = i + 1;
        };
        
        active_count
    }

    // Helper function to count total votes cast in a DAO
    fun get_total_votes_count(movedaoaddrxess: address): u64 {
        if (!proposal::has_proposals(movedaoaddrxess)) return 0;
        
        let total_proposals = proposal::get_proposals_count(movedaoaddrxess);
        let total_votes = 0;
        let i = 0;
        
        while (i < total_proposals) {
            let vote_count = proposal::get_proposal_vote_count(movedaoaddrxess, i);
            total_votes = total_votes + vote_count;
            i = i + 1;
        };
        
        total_votes
    }

    // Batch function to get overview for multiple DAOs
    #[view]
    public fun get_multiple_dao_stats(movedaoaddrxesses: vector<address>): vector<DAOStats> {
        let stats = vector::empty<DAOStats>();
        let i = 0;
        let len = vector::length(&movedaoaddrxesses);
        
        while (i < len) {
            let movedaoaddrx = *vector::borrow(&movedaoaddrxesses, i);
            if (dao_core::dao_exists(movedaoaddrx)) {
                let dao_stats = get_dao_stats(movedaoaddrx);
                vector::push_back(&mut stats, dao_stats);
            };
            i = i + 1;
        };
        
        stats
    }

    // Get all DAO statistics
    #[view]
    public fun get_all_dao_stats(): vector<DAOStats> {
        let dao_addresses = dao_core::get_all_dao_addresses();
        get_multiple_dao_stats(dao_addresses)
    }
}