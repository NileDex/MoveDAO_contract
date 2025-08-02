module dao_addr::proposal {
    use std::signer;
    use std::vector;
    use std::string;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use dao_addr::admin;
    use dao_addr::membership;
    use dao_addr::staking;
    use dao_addr::rewards;

    const STATUS_DRAFT: u8 = 0;
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_PASSED: u8 = 2;
    const STATUS_REJECTED: u8 = 3;
    const STATUS_EXECUTED: u8 = 4;
    const STATUS_CANCELLED: u8 = 5;

    const VOTE_YES: u8 = 1;
    const VOTE_NO: u8 = 2;
    const VOTE_ABSTAIN: u8 = 3;

    const ENOT_AUTHORIZED: u64 = 100;
    const EINVALID_STATUS: u64 = 101;
    const EVOTING_NOT_STARTED: u64 = 102;
    const EVOTING_ENDED: u64 = 103;
    const EALREADY_VOTED: u64 = 104;
    const ENO_SUCH_PROPOSAL: u64 = 105;
    const EQUORUM_NOT_MET: u64 = 106;
    const EEXECUTION_WINDOW_EXPIRED: u64 = 107;
    const ENOT_ADMIN_OR_PROPOSER: u64 = 108;
    const ECANNOT_CANCEL: u64 = 109;
    const EINVALID_VOTE_TYPE: u64 = 110;
    const ENOT_MEMBER: u64 = 111;

    struct Proposal has store, copy, drop {
        id: u64,
        title: string::String,
        description: string::String,
        proposer: address,
        status: u8,
        votes: vector<Vote>,
        yes_votes: u64,
        no_votes: u64,
        abstain_votes: u64,
        created_at: u64,
        voting_start: u64,
        voting_end: u64,
        execution_window: u64,
        min_quorum_percent: u64
    }

    struct Vote has store, copy, drop {
        voter: address,
        vote_type: u8,
        weight: u64,
        voted_at: u64
    }

    struct DaoProposals has key {
        proposals: vector<Proposal>,
        next_id: u64,
        min_voting_period: u64,
        max_voting_period: u64,
    }

    #[event]
    struct ProposalCreatedEvent has drop, store {
        proposal_id: u64,
        proposer: address,
        title: string::String,
    }

    #[event]
    struct ProposalStatusChangedEvent has drop, store {
        proposal_id: u64,
        old_status: u8,
        new_status: u8,
        reason: string::String,
    }

    #[event]
    struct VoteCastEvent has drop, store {
        proposal_id: u64,
        voter: address,
        vote_type: u8,
        weight: u64,
    }

    public fun initialize_proposals(
        account: &signer,
        min_voting_period: u64,
        max_voting_period: u64
    ) {
        let addr = signer::address_of(account);
        if (!exists<DaoProposals>(addr)) {
            let dao_proposals = DaoProposals {
                proposals: vector::empty(),
                next_id: 0,
                min_voting_period,
                max_voting_period,
            };

            move_to(account, dao_proposals);
        } else {
            // If already exists, abort
            abort ENOT_AUTHORIZED
        }
    }

    public entry fun create_proposal(
        account: &signer,
        dao_addr: address,
        title: string::String,
        description: string::String,
        voting_duration_secs: u64,
        execution_window_secs: u64,
        min_quorum_percent: u64
    ) acquires DaoProposals {
        let sender = signer::address_of(account);
        assert!(admin::is_admin(dao_addr, sender) || membership::is_member(dao_addr, sender), ENOT_AUTHORIZED);

        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        assert!(voting_duration_secs >= proposals.min_voting_period, EINVALID_STATUS);
        assert!(voting_duration_secs <= proposals.max_voting_period, EINVALID_STATUS);

        let now = timestamp::now_seconds();
        let proposal_id = proposals.next_id;

        let proposal = Proposal {
            id: proposal_id,
            title,
            description,
            proposer: sender,
            status: STATUS_DRAFT,
            votes: vector::empty(),
            yes_votes: 0,
            no_votes: 0,
            abstain_votes: 0,
            created_at: now,
            voting_start: now,
            voting_end: now + voting_duration_secs,
            execution_window: execution_window_secs,
            min_quorum_percent
        };

        vector::push_back(&mut proposals.proposals, proposal);
        proposals.next_id = proposal_id + 1;
        
        event::emit(ProposalCreatedEvent {
            proposal_id,
            proposer: sender,
            title: copy title,
        });

        // Distribute proposal creation reward
        rewards::distribute_proposal_creation_reward(dao_addr, sender, proposal_id);
    }

    public entry fun start_voting(
        account: &signer,
        dao_addr: address,
        proposal_id: u64
    ) acquires DaoProposals {
        let sender = signer::address_of(account);
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(proposal.status == STATUS_DRAFT, EINVALID_STATUS);
        assert!(
            proposal.proposer == sender || admin::is_admin(dao_addr, sender), 
            ENOT_ADMIN_OR_PROPOSER
        );

        proposal.status = STATUS_ACTIVE;
        event::emit(ProposalStatusChangedEvent {
            proposal_id,
            old_status: STATUS_DRAFT,
            new_status: STATUS_ACTIVE,
            reason: string::utf8(b"voting_started")
        });
    }

    public entry fun cast_vote(
        account: &signer,
        dao_addr: address,
        proposal_id: u64,
        vote_type: u8
    ) acquires DaoProposals {
        assert!(vote_type == VOTE_YES || vote_type == VOTE_NO || vote_type == VOTE_ABSTAIN, EINVALID_VOTE_TYPE);
        
        let sender = signer::address_of(account);
        assert!(membership::is_member(dao_addr, sender), ENOT_MEMBER);
        
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(proposal.status == STATUS_ACTIVE, EINVALID_STATUS);
        let now = timestamp::now_seconds();
        assert!(now >= proposal.voting_start, EVOTING_NOT_STARTED);
        assert!(now <= proposal.voting_end, EVOTING_ENDED);

        let i = 0;
        let len = vector::length(&proposal.votes);
        while (i < len) {
            let vote = vector::borrow(&proposal.votes, i);
            if (vote.voter == sender) abort EALREADY_VOTED;
            i = i + 1;
        };

        let weight = membership::get_voting_power(dao_addr, sender);
        assert!(weight > 0, ENOT_MEMBER);
        
        vector::push_back(&mut proposal.votes, Vote { 
            voter: sender, 
            vote_type, 
            weight,
            voted_at: now
        });

        if (vote_type == VOTE_YES) {
            proposal.yes_votes = proposal.yes_votes + weight;
        } else if (vote_type == VOTE_NO) {
            proposal.no_votes = proposal.no_votes + weight;
        } else {
            proposal.abstain_votes = proposal.abstain_votes + weight;
        };

        event::emit(VoteCastEvent {
            proposal_id,
            voter: sender,
            vote_type,
            weight,
        });

        // Distribute voting reward
        rewards::distribute_voting_reward(dao_addr, sender, proposal_id);
    }

    public entry fun finalize_proposal(
        account: &signer,
        dao_addr: address,
        proposal_id: u64
    ) acquires DaoProposals {
        let _sender = signer::address_of(account);
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(proposal.status == STATUS_ACTIVE, EINVALID_STATUS);
        let now = timestamp::now_seconds();
        assert!(now >= proposal.voting_end, EVOTING_ENDED);

        let total_staked = staking::get_total_staked(dao_addr);
        let total_votes = proposal.yes_votes + proposal.no_votes;
        let quorum = if (total_staked > 0) {
            total_votes * 100 / total_staked
        } else {
            0
        };
        
        if (quorum < proposal.min_quorum_percent) {
            let old_status = proposal.status;
            proposal.status = STATUS_REJECTED;
            event::emit(ProposalStatusChangedEvent {
                proposal_id,
                old_status,
                new_status: STATUS_REJECTED,
                reason: string::utf8(b"quorum_not_met")
            });
            return
        };

        let new_status = if (proposal.yes_votes > proposal.no_votes) STATUS_PASSED else STATUS_REJECTED;
        let old_status = proposal.status;
        proposal.status = new_status;
        
        event::emit(ProposalStatusChangedEvent {
            proposal_id,
            old_status,
            new_status,
            reason: string::utf8(b"vote_majority")
        });

        // Distribute successful proposal reward if it passed
        if (new_status == STATUS_PASSED) {
            rewards::distribute_successful_proposal_reward(dao_addr, proposal.proposer, proposal_id);
        };
    }

    public entry fun execute_proposal(
        account: &signer,
        dao_addr: address,
        proposal_id: u64
    ) acquires DaoProposals {
        let sender = signer::address_of(account);
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(proposal.status == STATUS_PASSED, EINVALID_STATUS);
        assert!(
            admin::is_admin(dao_addr, sender) || proposal.proposer == sender, 
            ENOT_ADMIN_OR_PROPOSER
        );
        
        let now = timestamp::now_seconds();
        assert!(now <= proposal.voting_end + proposal.execution_window, EEXECUTION_WINDOW_EXPIRED);

        let old_status = proposal.status;
        proposal.status = STATUS_EXECUTED;
        
        event::emit(ProposalStatusChangedEvent {
            proposal_id,
            old_status,
            new_status: STATUS_EXECUTED,
            reason: string::utf8(b"executed")
        });
    }

    public entry fun cancel_proposal(
        account: &signer,
        dao_addr: address,
        proposal_id: u64
    ) acquires DaoProposals {
        let sender = signer::address_of(account);
        let proposals = borrow_global_mut<DaoProposals>(dao_addr);
        let proposal = find_proposal_mut(&mut proposals.proposals, proposal_id);

        assert!(
            proposal.status == STATUS_DRAFT || proposal.status == STATUS_ACTIVE,
            ECANNOT_CANCEL
        );
        assert!(
            admin::is_admin(dao_addr, sender) || proposal.proposer == sender,
            ENOT_ADMIN_OR_PROPOSER
        );

        let old_status = proposal.status;
        proposal.status = STATUS_CANCELLED;
        
        event::emit(ProposalStatusChangedEvent {
            proposal_id,
            old_status,
            new_status: STATUS_CANCELLED,
            reason: string::utf8(b"cancelled")
        });
    }

    #[view]
    public fun get_proposal_status(dao_addr: address, proposal_id: u64): u8 acquires DaoProposals {
        let proposals = &borrow_global<DaoProposals>(dao_addr).proposals;
        let proposal = find_proposal(proposals, proposal_id);
        proposal.status
    }

    #[view]
    public fun get_proposal(dao_addr: address, proposal_id: u64): Proposal acquires DaoProposals {
        let proposals = &borrow_global<DaoProposals>(dao_addr).proposals;
        let proposal = find_proposal(proposals, proposal_id);
        *proposal
    }

    #[view]
    public fun get_proposals_count(dao_addr: address): u64 acquires DaoProposals {
        vector::length(&borrow_global<DaoProposals>(dao_addr).proposals)
    }

    fun find_proposal(proposals: &vector<Proposal>, proposal_id: u64): &Proposal {
        let i = 0;
        while (i < vector::length(proposals)) {
            let proposal = vector::borrow(proposals, i);
            if (proposal.id == proposal_id) return proposal;
            i = i + 1;
        };
        abort ENO_SUCH_PROPOSAL
    }

    fun find_proposal_mut(proposals: &mut vector<Proposal>, proposal_id: u64): &mut Proposal {
        let i = 0;
        while (i < vector::length(proposals)) {
            let proposal = vector::borrow_mut(proposals, i);
            if (proposal.id == proposal_id) return proposal;
            i = i + 1;
        };
        abort ENO_SUCH_PROPOSAL
    }

    #[view] public fun status_draft(): u8 { STATUS_DRAFT }
    #[view] public fun status_active(): u8 { STATUS_ACTIVE }
    #[view] public fun status_passed(): u8 { STATUS_PASSED }
    #[view] public fun status_rejected(): u8 { STATUS_REJECTED }
    #[view] public fun status_executed(): u8 { STATUS_EXECUTED }
    #[view] public fun status_cancelled(): u8 { STATUS_CANCELLED }
    
    #[view] public fun vote_yes(): u8 { VOTE_YES }
    #[view] public fun vote_no(): u8 { VOTE_NO }
    #[view] public fun vote_abstain(): u8 { VOTE_ABSTAIN }
}