use chainhope::events::{OwnershipTransferStarted, RequestClosed, RequestSubmitted, VoteCast};
use chainhope::interface::{IChainHopeDispatcher, IChainHopeDispatcherTrait};
use chainhope::types::RequestStatus;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_block_timestamp, start_cheat_caller_address, stop_cheat_block_timestamp,
    stop_cheat_caller_address,
};
use starknet::{ContractAddress, SyscallResultTrait};

// -----------------------------------------------
// CONSTANTS — test actors (modern syntax)
// -----------------------------------------------
fn OWNER() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'owner'>()
}
fn RECIPIENT() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'recipient'>()
}
fn DONOR_1() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'donor1'>()
}
fn DONOR_2() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'donor2'>()
}
fn VOTER_1() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'voter1'>()
}
fn VOTER_2() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'voter2'>()
}
fn VOTER_3() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'voter3'>()
}
fn STRANGER() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'stranger'>()
}
fn TOKEN() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'token'>()
}
fn NEW_OWNER() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<'new_owner'>()
}
fn ZERO_ADDRESS() -> ContractAddress {
    #[feature("deprecated-starknet-consts")]
    starknet::contract_address_const::<0>()
}

// -----------------------------------------------
// TEST CONSTANTS
// -----------------------------------------------
const VOTE_THRESHOLD: u64 = 3;
const AMOUNT_NEEDED: u256 = 1000_u256;
const DONATION_AMOUNT: u256 = 500_u256;
const IPFS_HASH: felt252 = 'QmTest123';
const TITLE: felt252 = 'Help John Doe';

// -----------------------------------------------
// HELPERS
// -----------------------------------------------

fn deploy_contract() -> IChainHopeDispatcher {
    let contract = declare("ChainHope").unwrap_syscall().contract_class();

    let mut constructor_args: Array<felt252> = array![];
    OWNER().serialize(ref constructor_args);
    VOTE_THRESHOLD.serialize(ref constructor_args);
    TOKEN().serialize(ref constructor_args);

    // ✅ Fixed — just unwrap, no unwrap_syscall
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap_syscall();
    IChainHopeDispatcher { contract_address }
}

fn deploy_with_request() -> (IChainHopeDispatcher, u64) {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    let request_id = chainhope.submit_request(IPFS_HASH, TITLE, AMOUNT_NEEDED);
    stop_cheat_caller_address(chainhope.contract_address);

    (chainhope, request_id)
}

fn deploy_with_approved_request() -> (IChainHopeDispatcher, u64) {
    let (chainhope, request_id) = deploy_with_request();

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_2());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_3());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    (chainhope, request_id)
}

fn deploy_expect_err(constructor_args: @Array<felt252>) -> felt252 {
    let contract = declare("ChainHope").unwrap_syscall().contract_class();
    match contract.deploy(constructor_args) {
        Result::Ok(_) => panic!("Deployment should have failed"),
        Result::Err(e) => *e.at(0),
    }
}

// -----------------------------------------------
// GROUP 1 — DEPLOYMENT & CONSTRUCTOR
// -----------------------------------------------

#[test]
fn test_constructor_sets_values_correctly() {
    let chainhope = deploy_contract();

    assert(chainhope.get_owner() == OWNER(), 'Owner not set correctly');
    assert(chainhope.get_vote_threshold() == VOTE_THRESHOLD, 'Threshold not set');
    assert(chainhope.get_accepted_token() == TOKEN(), 'Token not set');
    assert(chainhope.get_request_count() == 0, 'Count should be zero');
}

#[test]
fn test_revert_if_owner_is_zero_address() {
    let mut constructor_args: Array<felt252> = array![];
    ZERO_ADDRESS().serialize(ref constructor_args);
    VOTE_THRESHOLD.serialize(ref constructor_args);
    TOKEN().serialize(ref constructor_args);

    let err = deploy_expect_err(@constructor_args);
    assert(err == 'Zero address not allowed', 'Wrong error message');
}


#[test]
fn test_revert_if_vote_threshold_is_zero() {
    let mut constructor_args: Array<felt252> = array![];
    OWNER().serialize(ref constructor_args);
    0_u64.serialize(ref constructor_args);
    TOKEN().serialize(ref constructor_args);

    let err = deploy_expect_err(@constructor_args);
    assert(err == 'Amount must be greater than 0', 'Wrong error message');
}


#[test]
fn test_revert_if_token_is_zero_address() {
    let mut constructor_args: Array<felt252> = array![];
    OWNER().serialize(ref constructor_args);
    VOTE_THRESHOLD.serialize(ref constructor_args);
    ZERO_ADDRESS().serialize(ref constructor_args);

    let err = deploy_expect_err(@constructor_args);
    assert(err == 'Zero address not allowed', 'Wrong error message');
}

// -----------------------------------------------
// GROUP 2 — SUBMIT REQUEST
// -----------------------------------------------

#[test]
fn test_submit_request_succeeds() {
    let chainhope = deploy_contract();
    let mut spy = spy_events();

    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    let request_id = chainhope.submit_request(IPFS_HASH, TITLE, AMOUNT_NEEDED);
    stop_cheat_caller_address(chainhope.contract_address);

    assert(request_id == 0, 'Request ID should be 0');
    assert(chainhope.get_request_count() == 1, 'Count should be 1');

    let request = chainhope.get_request(request_id);
    assert(request.recipient == RECIPIENT(), 'Wrong recipient');
    assert(request.ipfs_hash == IPFS_HASH, 'Wrong ipfs hash');
    assert(request.title == TITLE, 'Wrong title');
    assert(request.amount_needed == AMOUNT_NEEDED, 'Wrong amount needed');
    assert(request.amount_raised == 0, 'Amount raised should be 0');
    assert(request.status == RequestStatus::Pending, 'Status should be Pending');
    assert(request.votes_for == 0, 'Votes for should be 0');
    assert(request.votes_against == 0, 'Votes against should be 0');

    spy
        .assert_emitted(
            @array![
                (
                    chainhope.contract_address,
                    chainhope::chainhope::ChainHope::Event::RequestSubmitted(
                        RequestSubmitted {
                            request_id,
                            recipient: RECIPIENT(),
                            ipfs_hash: IPFS_HASH,
                            amount_needed: AMOUNT_NEEDED,
                        },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: ('IPFS hash cannot be empty',))]
fn test_revert_if_ipfs_hash_is_empty() {
    let chainhope = deploy_contract();
    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    chainhope.submit_request(0, TITLE, AMOUNT_NEEDED);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Amount must be greater than 0',))]
fn test_revert_if_amount_needed_is_zero() {
    let chainhope = deploy_contract();
    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    chainhope.submit_request(IPFS_HASH, TITLE, 0);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
fn test_multiple_requests_get_sequential_ids() {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    let id_0 = chainhope.submit_request(IPFS_HASH, TITLE, AMOUNT_NEEDED);
    let id_1 = chainhope.submit_request(IPFS_HASH, TITLE, AMOUNT_NEEDED);
    let id_2 = chainhope.submit_request(IPFS_HASH, TITLE, AMOUNT_NEEDED);
    stop_cheat_caller_address(chainhope.contract_address);

    assert(id_0 == 0, 'First ID should be 0');
    assert(id_1 == 1, 'Second ID should be 1');
    assert(id_2 == 2, 'Third ID should be 2');
    assert(chainhope.get_request_count() == 3, 'Count should be 3');
}

// -----------------------------------------------
// GROUP 3 — VOTING
// -----------------------------------------------

#[test]
fn test_vote_approve_succeeds() {
    let (chainhope, request_id) = deploy_with_request();
    let mut spy = spy_events();

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.votes_for == 1, 'Votes for should be 1');
    assert(request.status == RequestStatus::Pending, 'Should still be pending');
    assert(chainhope.has_voted(request_id, VOTER_1()), 'Voter1 should be marked');

    spy
        .assert_emitted(
            @array![
                (
                    chainhope.contract_address,
                    chainhope::chainhope::ChainHope::Event::VoteCast(
                        VoteCast { request_id, voter: VOTER_1(), approved: true },
                    ),
                ),
            ],
        );
}

#[test]
fn test_vote_reject_succeeds() {
    let (chainhope, request_id) = deploy_with_request();

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_reject(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.votes_against == 1, 'Votes against should be 1');
}

#[test]
fn test_request_approved_when_threshold_reached() {
    let (chainhope, request_id) = deploy_with_request();

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_2());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.status == RequestStatus::Pending, 'Should be pending');

    start_cheat_caller_address(chainhope.contract_address, VOTER_3());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.status == RequestStatus::Approved, 'Should be approved');
    assert(request.votes_for == 3, 'Votes for should be 3');
}

#[test]
fn test_request_rejected_when_threshold_reached() {
    let (chainhope, request_id) = deploy_with_request();

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_reject(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_2());
    chainhope.vote_reject(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_3());
    chainhope.vote_reject(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.status == RequestStatus::Rejected, 'Should be rejected');
    assert(request.votes_against == 3, 'Votes against should be 3');
}

#[test]
#[should_panic(expected: ('Already voted on request',))]
fn test_revert_if_double_vote() {
    let (chainhope, request_id) = deploy_with_request();

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(request_id);
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Recipient cannot vote',))]
fn test_revert_if_recipient_votes() {
    let (chainhope, request_id) = deploy_with_request();

    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Request is not pending',))]
fn test_revert_if_vote_on_approved_request() {
    let (chainhope, request_id) = deploy_with_approved_request();

    start_cheat_caller_address(chainhope.contract_address, STRANGER());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);
}


#[test]
#[should_panic(expected: ('Request does not exist',))]
fn test_revert_if_vote_on_invalid_request() {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(999);
    stop_cheat_caller_address(chainhope.contract_address);
}

// -----------------------------------------------
// GROUP 4 — CLOSE REQUEST
// -----------------------------------------------

#[test]
fn test_owner_can_close_request() {
    let (chainhope, request_id) = deploy_with_approved_request();
    let mut spy = spy_events();

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.close_request(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.status == RequestStatus::Closed, 'Should be closed');

    spy
        .assert_emitted(
            @array![
                (
                    chainhope.contract_address,
                    chainhope::chainhope::ChainHope::Event::RequestClosed(
                        RequestClosed { request_id },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: ('Caller is not owner',))]
fn test_revert_if_stranger_closes_request() {
    let (chainhope, request_id) = deploy_with_approved_request();

    start_cheat_caller_address(chainhope.contract_address, STRANGER());
    chainhope.close_request(request_id);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Request already closed',))]
fn test_revert_if_close_already_closed_request() {
    let (chainhope, request_id) = deploy_with_approved_request();

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.close_request(request_id);
    chainhope.close_request(request_id);
    stop_cheat_caller_address(chainhope.contract_address);
}

// -----------------------------------------------
// GROUP 5 — OWNERSHIP
// -----------------------------------------------

#[test]
fn test_transfer_ownership_two_step() {
    let chainhope = deploy_contract();
    let mut spy = spy_events();

    // Step 1 — owner proposes transfer
    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.transfer_ownership(NEW_OWNER());
    stop_cheat_caller_address(chainhope.contract_address);

    // Owner hasn't changed yet
    assert(chainhope.get_owner() == OWNER(), 'Owner should not change yet');
    assert(chainhope.get_pending_owner() == NEW_OWNER(), 'Pending owner should be set');

    spy
        .assert_emitted(
            @array![
                (
                    chainhope.contract_address,
                    chainhope::chainhope::ChainHope::Event::OwnershipTransferStarted(
                        OwnershipTransferStarted {
                            previous_owner: OWNER(), new_owner: NEW_OWNER(),
                        },
                    ),
                ),
            ],
        );

    // Step 2 — new owner accepts
    start_cheat_caller_address(chainhope.contract_address, NEW_OWNER());
    chainhope.accept_ownership();
    stop_cheat_caller_address(chainhope.contract_address);

    assert(chainhope.get_owner() == NEW_OWNER(), 'Owner should be new owner');
    assert(
        chainhope.get_pending_owner() == ZERO_ADDRESS(), // ✅ modern syntax
        'Pending owner should be cleared',
    );
}

#[test]
#[should_panic(expected: ('Caller is not owner',))]
fn test_revert_if_stranger_transfers_ownership() {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, STRANGER());
    chainhope.transfer_ownership(NEW_OWNER());
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not owner',))]
fn test_revert_if_wrong_address_accepts_ownership() {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.transfer_ownership(NEW_OWNER());
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, STRANGER());
    chainhope.accept_ownership();
    stop_cheat_caller_address(chainhope.contract_address);
}

// -----------------------------------------------
// GROUP 6 — VOTE THRESHOLD
// -----------------------------------------------

#[test]
fn test_owner_can_set_vote_threshold() {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.propose_vote_threshold(5);
    stop_cheat_caller_address(chainhope.contract_address);

    // Advance time past timelock
    start_cheat_block_timestamp(chainhope.contract_address, 86401_u64);

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.execute_vote_threshold();
    stop_cheat_caller_address(chainhope.contract_address);

    stop_cheat_block_timestamp(chainhope.contract_address);

    assert(chainhope.get_vote_threshold() == 5, 'Threshold should be 5');
}

#[test]
#[should_panic(expected: ('Timelock has not expired',))]
fn test_revert_if_execute_threshold_before_timelock() {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.propose_vote_threshold(5);
    chainhope.execute_vote_threshold();
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not owner',))]
fn test_revert_if_stranger_sets_threshold() {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, STRANGER());
    chainhope.propose_vote_threshold(5);
    stop_cheat_caller_address(chainhope.contract_address);
}

// -----------------------------------------------
// GROUP 7 — TOKEN WHITELIST
// -----------------------------------------------

#[test]
fn test_owner_can_whitelist_token() {
    let chainhope = deploy_contract();
    #[feature("deprecated-starknet-consts")]
    let new_token = starknet::contract_address_const::<'new_token'>(); // ✅ modern

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.whitelist_token(new_token);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Caller is not owner',))]
fn test_revert_if_stranger_whitelists_token() {
    let chainhope = deploy_contract();
    #[feature("deprecated-starknet-consts")]
    let new_token = starknet::contract_address_const::<'new_token'>(); // ✅ modern

    start_cheat_caller_address(chainhope.contract_address, STRANGER());
    chainhope.whitelist_token(new_token);
    stop_cheat_caller_address(chainhope.contract_address);
}

// -----------------------------------------------
// GROUP 8 — PAUSE
// -----------------------------------------------

#[test]
#[should_panic(expected: ('Contract is paused',))]
fn test_revert_if_vote_when_paused() {
    let (chainhope, request_id) = deploy_with_request();

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.pause();
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
fn test_owner_can_unpause() {
    let (chainhope, request_id) = deploy_with_request();

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.pause();
    chainhope.unpause();
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.votes_for == 1, 'Vote should have gone through');
}

// -----------------------------------------------
// GROUP 9 — FULL FLOW INTEGRATION
// -----------------------------------------------

#[test]
fn test_full_flow_submit_vote_approve() {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    let request_id = chainhope.submit_request(IPFS_HASH, TITLE, AMOUNT_NEEDED);
    stop_cheat_caller_address(chainhope.contract_address);

    assert(chainhope.get_request(request_id).status == RequestStatus::Pending, 'Should be pending');

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_2());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_3());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.status == RequestStatus::Approved, 'Should be approved');
    assert(request.votes_for == 3, 'Should have 3 votes');

    start_cheat_caller_address(chainhope.contract_address, OWNER());
    chainhope.close_request(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    assert(chainhope.get_request(request_id).status == RequestStatus::Closed, 'Should be closed');
}

#[test]
fn test_full_flow_submit_vote_reject() {
    let chainhope = deploy_contract();

    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    let request_id = chainhope.submit_request(IPFS_HASH, TITLE, AMOUNT_NEEDED);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_2());
    chainhope.vote_reject(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_3());
    chainhope.vote_reject(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, DONOR_1());
    chainhope.vote_reject(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.status == RequestStatus::Rejected, 'Should be rejected');
}
