// tests/test_donate.cairo
use chainhope::events::DonationReceived;
use chainhope::interface::{IChainHopeDispatcher, IChainHopeDispatcherTrait};
use chainhope::types::RequestStatus;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress, SyscallResultTrait};
use crate::mock_erc20::{IMockERC20Dispatcher, IMockERC20DispatcherTrait};

// -----------------------------------------------
// CONSTANTS
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

const VOTE_THRESHOLD: u64 = 3;
const AMOUNT_NEEDED: u256 = 1000_u256;
const DONATION_AMOUNT: u256 = 500_u256;
const IPFS_HASH: felt252 = 'QmTest123';
const TITLE: felt252 = 'Help John Doe';

// -----------------------------------------------
// HELPERS
// -----------------------------------------------
fn deploy_mock_token() -> IMockERC20Dispatcher {
    let contract = declare("MockERC20").unwrap_syscall().contract_class();
    let constructor_args: Array<felt252> = array![];
    let (contract_address, _) = contract.deploy(@constructor_args).unwrap_syscall();
    IMockERC20Dispatcher { contract_address }
}

fn deploy_contract_with_token() -> (IChainHopeDispatcher, IMockERC20Dispatcher) {
    let token = deploy_mock_token();

    let contract = declare("ChainHope").unwrap_syscall().contract_class();
    let mut constructor_args: Array<felt252> = array![];
    OWNER().serialize(ref constructor_args);
    VOTE_THRESHOLD.serialize(ref constructor_args);
    token.contract_address.serialize(ref constructor_args);

    let (contract_address, _) = contract.deploy(@constructor_args).unwrap_syscall();
    let chainhope = IChainHopeDispatcher { contract_address };

    (chainhope, token)
}

fn deploy_with_approved_request_and_token() -> (IChainHopeDispatcher, IMockERC20Dispatcher, u64) {
    let (chainhope, token) = deploy_contract_with_token();

    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    let request_id = chainhope.submit_request(IPFS_HASH, TITLE, AMOUNT_NEEDED);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_1());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_2());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, VOTER_3());
    chainhope.vote_approve(request_id);
    stop_cheat_caller_address(chainhope.contract_address);

    (chainhope, token, request_id)
}

// -----------------------------------------------
// GROUP 10 — DONATE
// -----------------------------------------------

#[test]
fn test_donate_succeeds() {
    let (chainhope, token, request_id) = deploy_with_approved_request_and_token();
    let mut spy = spy_events();

    token.mint(DONOR_1(), DONATION_AMOUNT);

    start_cheat_caller_address(token.contract_address, DONOR_1());
    token.approve(chainhope.contract_address, DONATION_AMOUNT);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(chainhope.contract_address, DONOR_1());
    chainhope.donate(request_id, DONATION_AMOUNT);
    stop_cheat_caller_address(chainhope.contract_address);

    assert(token.balance_of(RECIPIENT()) == DONATION_AMOUNT, 'Recipient should have tokens');
    assert(token.balance_of(chainhope.contract_address) == 0, 'Contract should hold nothing');

    let request = chainhope.get_request(request_id);
    assert(request.amount_raised == DONATION_AMOUNT, 'Amount raised wrong');
    assert(request.donor_count == 1, 'Donor count should be 1');
    assert(chainhope.get_total_donated(request_id) == DONATION_AMOUNT, 'Total donated wrong');

    spy
        .assert_emitted(
            @array![
                (
                    chainhope.contract_address,
                    chainhope::chainhope::ChainHope::Event::DonationReceived(
                        DonationReceived {
                            request_id,
                            donor: DONOR_1(),
                            amount: DONATION_AMOUNT,
                            total_raised: DONATION_AMOUNT,
                        },
                    ),
                ),
            ],
        );
}

#[test]
fn test_multiple_donations_accumulate() {
    let (chainhope, token, request_id) = deploy_with_approved_request_and_token();

    token.mint(DONOR_1(), DONATION_AMOUNT);
    token.mint(DONOR_2(), DONATION_AMOUNT);

    start_cheat_caller_address(token.contract_address, DONOR_1());
    token.approve(chainhope.contract_address, DONATION_AMOUNT);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(token.contract_address, DONOR_2());
    token.approve(chainhope.contract_address, DONATION_AMOUNT);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(chainhope.contract_address, DONOR_1());
    chainhope.donate(request_id, DONATION_AMOUNT);
    stop_cheat_caller_address(chainhope.contract_address);

    start_cheat_caller_address(chainhope.contract_address, DONOR_2());
    chainhope.donate(request_id, DONATION_AMOUNT);
    stop_cheat_caller_address(chainhope.contract_address);

    assert(
        token.balance_of(RECIPIENT()) == DONATION_AMOUNT * 2,
        'Recipient should have both' // ✅ fixed — no Errors:: reference
    );

    let request = chainhope.get_request(request_id);
    assert(request.amount_raised == DONATION_AMOUNT * 2, 'Amount raised wrong');
    assert(request.donor_count == 2, 'Donor count should be 2');
}

#[test]
fn test_request_marked_funded_when_target_reached() {
    let (chainhope, token, request_id) = deploy_with_approved_request_and_token();

    token.mint(DONOR_1(), AMOUNT_NEEDED);

    start_cheat_caller_address(token.contract_address, DONOR_1());
    token.approve(chainhope.contract_address, AMOUNT_NEEDED);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(chainhope.contract_address, DONOR_1());
    chainhope.donate(request_id, AMOUNT_NEEDED);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.status == RequestStatus::Funded, 'Should be funded');
    assert(request.amount_raised == AMOUNT_NEEDED, 'Full amount raised');
}

#[test]
#[should_panic(expected: ('Amount must be greater than 0',))]
fn test_revert_if_donate_zero_amount() {
    let (chainhope, _, request_id) = deploy_with_approved_request_and_token();

    start_cheat_caller_address(chainhope.contract_address, DONOR_1());
    chainhope.donate(request_id, 0);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Insufficient token allowance',))]
fn test_revert_if_insufficient_allowance() {
    let (chainhope, token, request_id) = deploy_with_approved_request_and_token();

    token.mint(DONOR_1(), DONATION_AMOUNT);

    start_cheat_caller_address(token.contract_address, DONOR_1());
    token.approve(chainhope.contract_address, 100_u256);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(chainhope.contract_address, DONOR_1());
    chainhope.donate(request_id, DONATION_AMOUNT);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Request not approved',))]
fn test_revert_if_donate_to_pending_request() {
    let (chainhope, token) = deploy_contract_with_token();

    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    let request_id = chainhope.submit_request(IPFS_HASH, TITLE, AMOUNT_NEEDED);
    stop_cheat_caller_address(chainhope.contract_address);

    token.mint(DONOR_1(), DONATION_AMOUNT);

    start_cheat_caller_address(token.contract_address, DONOR_1());
    token.approve(chainhope.contract_address, DONATION_AMOUNT);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(chainhope.contract_address, DONOR_1());
    chainhope.donate(request_id, DONATION_AMOUNT);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Recipient cannot self donate',))]
fn test_revert_if_recipient_self_donates() {
    let (chainhope, token, request_id) = deploy_with_approved_request_and_token();

    token.mint(RECIPIENT(), DONATION_AMOUNT);

    start_cheat_caller_address(token.contract_address, RECIPIENT());
    token.approve(chainhope.contract_address, DONATION_AMOUNT);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(chainhope.contract_address, RECIPIENT());
    chainhope.donate(request_id, DONATION_AMOUNT);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
#[should_panic(expected: ('Request does not exist',))]
fn test_revert_if_donate_to_invalid_request() {
    let (chainhope, token, _) = deploy_with_approved_request_and_token();

    token.mint(DONOR_1(), DONATION_AMOUNT);

    start_cheat_caller_address(token.contract_address, DONOR_1());
    token.approve(chainhope.contract_address, DONATION_AMOUNT);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(chainhope.contract_address, DONOR_1());
    chainhope.donate(999, DONATION_AMOUNT);
    stop_cheat_caller_address(chainhope.contract_address);
}

#[test]
fn test_full_donate_flow() {
    let (chainhope, token, request_id) = deploy_with_approved_request_and_token();

    token.mint(DONOR_1(), DONATION_AMOUNT);
    token.mint(DONOR_2(), AMOUNT_NEEDED - DONATION_AMOUNT);

    start_cheat_caller_address(token.contract_address, DONOR_1());
    token.approve(chainhope.contract_address, DONATION_AMOUNT);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(token.contract_address, DONOR_2());
    token.approve(chainhope.contract_address, AMOUNT_NEEDED - DONATION_AMOUNT);
    stop_cheat_caller_address(token.contract_address);

    start_cheat_caller_address(chainhope.contract_address, DONOR_1());
    chainhope.donate(request_id, DONATION_AMOUNT);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.status == RequestStatus::Approved, 'Should still be approved');
    assert(request.amount_raised == DONATION_AMOUNT, 'Partial amount raised');

    start_cheat_caller_address(chainhope.contract_address, DONOR_2());
    chainhope.donate(request_id, AMOUNT_NEEDED - DONATION_AMOUNT);
    stop_cheat_caller_address(chainhope.contract_address);

    let request = chainhope.get_request(request_id);
    assert(request.status == RequestStatus::Funded, 'Should be funded');
    assert(request.amount_raised == AMOUNT_NEEDED, 'Full amount raised');

    assert(token.balance_of(RECIPIENT()) == AMOUNT_NEEDED, 'Recipient has full amount');
    assert(token.balance_of(chainhope.contract_address) == 0, 'Contract should be empty');
}
