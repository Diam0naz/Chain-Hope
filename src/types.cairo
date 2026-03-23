use starknet::ContractAddress;

#[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
pub enum RequestStatus {
    #[default]
    Pending, // 0 - submitted, awaiting votes
    Approved, // 1 - community voted to approve
    Rejected, // 2 - community voted to reject
    Funded, // 3 - fully funded
    Closed // 4 - completed/closed
}

// The core charity request struct
#[derive(Drop, Serde, starknet::Store, PartialEq, Copy)]
pub struct CharityRequest {
    pub id: u64, // unique request ID
    pub recipient: ContractAddress, // wallet to receive donations
    pub ipfs_hash: felt252, // proof of need document on IPFS
    pub title: felt252, // short title
    pub amount_needed: u256, // target amount in wei
    pub amount_raised: u256, // current amount raised
    pub status: RequestStatus, // current status
    pub votes_for: u64, // approve votes
    pub votes_against: u64, // reject votes
    pub created_at: u64, // block timestamp
    pub donor_count: u64 // number of unique donors
}

// Individual donation record
#[derive(Drop, Serde, starknet::Store, Copy, PartialEq)]
pub struct Donation {
    pub donor: ContractAddress,
    pub amount: u256,
    pub timestamp: u64,
}
