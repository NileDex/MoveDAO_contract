// Rewards system - distributes incentives to members for voting, creating proposals, and active participation
module movedaoaddrx::rewards {
    use std::signer;
    use std::vector;
    use std::simple_map::{Self, SimpleMap};
    use std::event;
    use aptos_framework::timestamp;
    use movedaoaddrx::admin;
    use movedaoaddrx::errors;


    // Reward types
    const REWARD_VOTING: u8 = 1;
    const REWARD_PROPOSAL_CREATION: u8 = 2;
    const REWARD_STAKING: u8 = 3;
    const REWARD_PROPOSAL_SUCCESS: u8 = 4;

    struct RewardConfig has key {
        voting_reward_per_vote: u64,
        proposal_creation_reward: u64,
        successful_proposal_reward: u64,
        staking_yield_rate: u64, // Annual percentage (e.g., 500 = 5%)
        last_staking_distribution: u64,
        staking_distribution_interval: u64, // Seconds between distributions
        total_rewards_distributed: u64,
        enabled: bool
    }

    struct PendingReward has store, copy, drop {
        recipient: address,
        amount: u64,
        reward_type: u8,
        created_at: u64,
        claimed: bool,
        proposal_id: u64 // For proposal-related rewards
    }

    struct RewardTracker has key {
        pending_rewards: vector<PendingReward>,
        claimed_rewards: SimpleMap<address, u64>, // Total claimed by user
        next_reward_id: u64
    }

    #[event]
    struct RewardDistributed has drop, store {
        recipient: address,
        amount: u64,
        reward_type: u8,
        proposal_id: u64,
        distributed_at: u64
    }

    #[event]
    struct RewardClaimed has drop, store {
        recipient: address,
        amount: u64,
        reward_type: u8,
        claimed_at: u64
    }

    #[event]
    struct StakingRewardsDistributed has drop, store {
        total_amount: u64,
        total_recipients: u64,
        distributed_at: u64
    }

    public fun initialize_rewards(
        account: &signer,
        voting_reward_per_vote: u64,
        proposal_creation_reward: u64,
        successful_proposal_reward: u64,
        staking_yield_rate: u64,
        staking_distribution_interval: u64
    ) {
        let addr = signer::address_of(account);
        assert!(!exists<RewardConfig>(addr), errors::already_exists());
        assert!(!exists<RewardTracker>(addr), errors::already_exists());

        let config = RewardConfig {
            voting_reward_per_vote,
            proposal_creation_reward,
            successful_proposal_reward,
            staking_yield_rate,
            last_staking_distribution: timestamp::now_seconds(),
            staking_distribution_interval,
            total_rewards_distributed: 0,
            enabled: true
        };

        let tracker = RewardTracker {
            pending_rewards: vector::empty(),
            claimed_rewards: simple_map::new(),
            next_reward_id: 0
        };

        move_to(account, config);
        move_to(account, tracker);
    }

    #[view]
    public fun is_rewards_enabled(movedaoaddrx: address): bool acquires RewardConfig {
        if (!exists<RewardConfig>(movedaoaddrx)) {
            return false
        };
        let config = borrow_global<RewardConfig>(movedaoaddrx);
        config.enabled
    }

    // Check if rewards system is initialized for a DAO
    #[view]
    public fun is_rewards_initialized(movedaoaddrx: address): bool {
        exists<RewardConfig>(movedaoaddrx) && exists<RewardTracker>(movedaoaddrx)
    }

    public fun distribute_voting_reward(
        movedaoaddrx: address,
        voter: address,
        proposal_id: u64
    ) acquires RewardConfig, RewardTracker {

        let config = borrow_global<RewardConfig>(movedaoaddrx);
        if (!config.enabled) return;

        let amount = config.voting_reward_per_vote;
        if (amount == 0) return;

        create_pending_reward(movedaoaddrx, voter, amount, REWARD_VOTING, proposal_id);
    }

    public fun distribute_proposal_creation_reward(
        movedaoaddrx: address,
        proposer: address,
        proposal_id: u64
    ) acquires RewardConfig, RewardTracker {

        let config = borrow_global<RewardConfig>(movedaoaddrx);
        if (!config.enabled) return;

        let amount = config.proposal_creation_reward;
        if (amount == 0) return;

        create_pending_reward(movedaoaddrx, proposer, amount, REWARD_PROPOSAL_CREATION, proposal_id);
    }

    public fun distribute_successful_proposal_reward(
        movedaoaddrx: address,
        proposer: address,
        proposal_id: u64
    ) acquires RewardConfig, RewardTracker {

        let config = borrow_global<RewardConfig>(movedaoaddrx);
        if (!config.enabled) return;

        let amount = config.successful_proposal_reward;
        if (amount == 0) return;

        create_pending_reward(movedaoaddrx, proposer, amount, REWARD_PROPOSAL_SUCCESS, proposal_id);
    }

    public entry fun distribute_staking_rewards(
        admin: &signer,
        movedaoaddrx: address,
        stakers: vector<address>,
        staked_amounts: vector<u64>
    ) acquires RewardConfig, RewardTracker {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        assert!(vector::length(&stakers) == vector::length(&staked_amounts), errors::invalid_amount());

        let config = borrow_global_mut<RewardConfig>(movedaoaddrx);
        if (!config.enabled) return;

        let now = timestamp::now_seconds();
        let time_elapsed = now - config.last_staking_distribution;
        
        if (time_elapsed < config.staking_distribution_interval) return;

        let total_distributed = 0;
        let recipient_count = vector::length(&stakers);
        let i = 0;

        while (i < recipient_count) {
            let staker = *vector::borrow(&stakers, i);
            let staked_amount = *vector::borrow(&staked_amounts, i);
            
            if (staked_amount > 0) {
                // Calculate annual yield: (staked_amount * yield_rate * time_elapsed) / (365 * 24 * 3600 * 10000)
                let annual_seconds = 365 * 24 * 3600;
                let denominator = annual_seconds * 10000;
                
                // Overflow protection for reward calculation
                assert!(staked_amount <= (18446744073709551615u64 / config.staking_yield_rate), errors::invalid_amount());
                let numerator_part1 = staked_amount * config.staking_yield_rate;
                assert!(numerator_part1 <= (18446744073709551615u64 / time_elapsed), errors::invalid_amount());
                let reward_amount = (numerator_part1 * time_elapsed) / denominator;
                
                if (reward_amount > 0) {
                    create_pending_reward(movedaoaddrx, staker, reward_amount, REWARD_STAKING, 0);
                    // Add overflow protection for total_distributed
                    assert!(total_distributed <= (18446744073709551615u64 - reward_amount), errors::invalid_amount());
                    total_distributed = total_distributed + reward_amount;
                };
            };
            i = i + 1;
        };

        config.last_staking_distribution = now;
        
        event::emit(StakingRewardsDistributed {
            total_amount: total_distributed,
            total_recipients: recipient_count,
            distributed_at: now
        });
    }

    public entry fun claim_rewards(
        account: &signer,
        movedaoaddrx: address
    ) acquires RewardTracker, RewardConfig {
        let user_addr = signer::address_of(account);
        
        // Check if user has any claimable rewards before proceeding
        let total_claimable = get_total_claimable(movedaoaddrx, user_addr);
        assert!(total_claimable > 0, errors::nothing_to_claim());
        
        // Process the claim and get the actual amount claimed
        let claimed_amount = claim_rewards_internal(movedaoaddrx, user_addr);
        
        // Only emit event if there were actually rewards to claim
        if (claimed_amount > 0) {
            event::emit(RewardClaimed {
                recipient: user_addr,
                amount: claimed_amount,
                reward_type: 0, // General claim event
                claimed_at: timestamp::now_seconds()
            });
        };
    }

    public fun claim_rewards_internal(
        movedaoaddrx: address,
        user_addr: address
    ): u64 acquires RewardTracker, RewardConfig {
        let tracker = borrow_global_mut<RewardTracker>(movedaoaddrx);
        let config = borrow_global_mut<RewardConfig>(movedaoaddrx);
        
        let total_claimable = 0;
        let rewards_len = vector::length(&tracker.pending_rewards);
        let i = 0;

        // Single atomic pass: identify and immediately claim rewards to prevent race conditions
        while (i < rewards_len) {
            let reward = vector::borrow_mut(&mut tracker.pending_rewards, i);
            if (reward.recipient == user_addr && !reward.claimed) {
                // Add overflow protection
                assert!(total_claimable <= (18446744073709551615u64 - reward.amount), errors::invalid_amount());
                
                // Atomically mark as claimed and add to total (prevents race conditions)
                reward.claimed = true;
                total_claimable = total_claimable + reward.amount;
                
                event::emit(RewardClaimed {
                    recipient: user_addr,
                    amount: reward.amount,
                    reward_type: reward.reward_type,
                    claimed_at: timestamp::now_seconds()
                });
            };
            i = i + 1;
        };

        // Update claimed totals with overflow protection
        if (simple_map::contains_key(&tracker.claimed_rewards, &user_addr)) {
            let current_total = simple_map::borrow_mut(&mut tracker.claimed_rewards, &user_addr);
            assert!(*current_total <= (18446744073709551615u64 - total_claimable), errors::invalid_amount());
            *current_total = *current_total + total_claimable;
        } else {
            simple_map::add(&mut tracker.claimed_rewards, user_addr, total_claimable);
        };

        // Update global total with overflow protection
        assert!(config.total_rewards_distributed <= (18446744073709551615u64 - total_claimable), errors::invalid_amount());
        config.total_rewards_distributed = config.total_rewards_distributed + total_claimable;
        total_claimable
    }

    public entry fun update_reward_config(
        admin: &signer,
        movedaoaddrx: address,
        voting_reward_per_vote: u64,
        proposal_creation_reward: u64,
        successful_proposal_reward: u64,
        staking_yield_rate: u64
    ) acquires RewardConfig {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        
        let config = borrow_global_mut<RewardConfig>(movedaoaddrx);
        config.voting_reward_per_vote = voting_reward_per_vote;
        config.proposal_creation_reward = proposal_creation_reward;
        config.successful_proposal_reward = successful_proposal_reward;
        config.staking_yield_rate = staking_yield_rate;
    }

    public entry fun toggle_rewards(
        admin: &signer,
        movedaoaddrx: address,
        enabled: bool
    ) acquires RewardConfig {
        assert!(admin::is_admin(movedaoaddrx, signer::address_of(admin)), errors::not_admin());
        
        let config = borrow_global_mut<RewardConfig>(movedaoaddrx);
        config.enabled = enabled;
    }

    #[view]
    public fun get_pending_rewards(movedaoaddrx: address, user: address): vector<PendingReward> acquires RewardTracker {
        let tracker = borrow_global<RewardTracker>(movedaoaddrx);
        let user_rewards = vector::empty();
        let len = vector::length(&tracker.pending_rewards);
        let i = 0;

        while (i < len) {
            let reward = vector::borrow(&tracker.pending_rewards, i);
            if (reward.recipient == user && !reward.claimed) {
                vector::push_back(&mut user_rewards, *reward);
            };
            i = i + 1;
        };

        user_rewards
    }

    #[view]
    public fun get_total_claimable(movedaoaddrx: address, user: address): u64 acquires RewardTracker {
        let tracker = borrow_global<RewardTracker>(movedaoaddrx);
        let total = 0;
        let len = vector::length(&tracker.pending_rewards);
        let i = 0;

        while (i < len) {
            let reward = vector::borrow(&tracker.pending_rewards, i);
            if (reward.recipient == user && !reward.claimed) {
                total = total + reward.amount;
            };
            i = i + 1;
        };

        total
    }

    #[view]
    public fun get_total_claimed(movedaoaddrx: address, user: address): u64 acquires RewardTracker {
        let tracker = borrow_global<RewardTracker>(movedaoaddrx);
        if (simple_map::contains_key(&tracker.claimed_rewards, &user)) {
            *simple_map::borrow(&tracker.claimed_rewards, &user)
        } else {
            0
        }
    }

    #[view]
    public fun get_reward_config(movedaoaddrx: address): (u64, u64, u64, u64, u64, bool) acquires RewardConfig {
        let config = borrow_global<RewardConfig>(movedaoaddrx);
        (
            config.voting_reward_per_vote,
            config.proposal_creation_reward,
            config.successful_proposal_reward,
            config.staking_yield_rate,
            config.total_rewards_distributed,
            config.enabled
        )
    }

    // Helper functions
    fun create_pending_reward(
        movedaoaddrx: address,
        recipient: address,
        amount: u64,
        reward_type: u8,
        proposal_id: u64
    ) acquires RewardTracker {
        let tracker = borrow_global_mut<RewardTracker>(movedaoaddrx);
        let now = timestamp::now_seconds();

        let reward = PendingReward {
            recipient,
            amount,
            reward_type,
            created_at: now,
            claimed: false,
            proposal_id
        };

        vector::push_back(&mut tracker.pending_rewards, reward);
        tracker.next_reward_id = tracker.next_reward_id + 1;

        event::emit(RewardDistributed {
            recipient,
            amount,
            reward_type,
            proposal_id,
            distributed_at: now
        });
    }

    // Public constants for reward types
    public fun reward_voting(): u8 { REWARD_VOTING }
    public fun reward_proposal_creation(): u8 { REWARD_PROPOSAL_CREATION }
    public fun reward_staking(): u8 { REWARD_STAKING }
    public fun reward_proposal_success(): u8 { REWARD_PROPOSAL_SUCCESS }
}