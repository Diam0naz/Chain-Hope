use starknet::ContractAddress;

#[starknet::interface]
pub trait IMockERC20<TContractState> {
    fn mint(ref self: TContractState, recipient: ContractAddress, amount: u256);
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256);
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256,
    ) -> bool;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn allowance(
        self: @TContractState,
        owner: ContractAddress,
        spender: ContractAddress,
    ) -> u256;
}

#[starknet::contract]
pub mod MockERC20 {
    use starknet::{
        ContractAddress,
        get_caller_address,
    };
    use starknet::storage::{
        Map,
        StorageMapReadAccess,
        StorageMapWriteAccess,
        StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use super::IMockERC20;

    #[storage]
    struct Storage {
        balances: Map<ContractAddress, u256>,
        allowances: Map<(ContractAddress, ContractAddress), u256>,
        total_supply: u256,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.total_supply.write(0);
    }

    #[abi(embed_v0)]
    impl MockERC20Impl of IMockERC20<ContractState> {

        // Mint tokens to any address — only for testing
        fn mint(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            let current = self.balances.read(recipient);
            self.balances.write(recipient, current + amount);
            self.total_supply.write(self.total_supply.read() + amount);
        }

        // Approve spender to spend amount on behalf of caller
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) {
            let caller = get_caller_address();
            self.allowances.write((caller, spender), amount);
        }

        // Transfer from caller to recipient
        fn transfer(
            ref self: ContractState,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let caller = get_caller_address();
            let caller_balance = self.balances.read(caller);
            assert(caller_balance >= amount, 'Insufficient balance');

            self.balances.write(caller, caller_balance - amount);
            let recipient_balance = self.balances.read(recipient);
            self.balances.write(recipient, recipient_balance + amount);
            true
        }

        // Transfer from sender to recipient using allowance
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            let caller = get_caller_address();

            // Check and reduce allowance
            let current_allowance = self.allowances.read((sender, caller));
            assert(current_allowance >= amount, 'Insufficient allowance');
            self.allowances.write((sender, caller), current_allowance - amount);

            // Transfer balance
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 'Insufficient balance');
            self.balances.write(sender, sender_balance - amount);

            let recipient_balance = self.balances.read(recipient);
            self.balances.write(recipient, recipient_balance + amount);
            true
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn allowance(
            self: @ContractState,
            owner: ContractAddress,
            spender: ContractAddress,
        ) -> u256 {
            self.allowances.read((owner, spender))
        }
    }
}