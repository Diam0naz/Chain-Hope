use starknet::ContractAddress;

// This is the interface of any ERC20 token contract
// We use it to call transferFrom and transfer
#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transfer(
        ref self: TContractState,
        recipient: ContractAddress,
        amount: u256
    ) -> bool;

    fn transfer_from(
        ref self: TContractState,
        sender: ContractAddress,
        recipient: ContractAddress,
        amount: u256
    ) -> bool;

    fn approve(
        ref self: TContractState,
        spender: ContractAddress,
        amount: u256
    ) -> bool;

    fn balance_of(
        self: @TContractState,
        account: ContractAddress
    ) -> u256;

    fn allowance(
        self: @TContractState,
        owner: ContractAddress,
        spender: ContractAddress
    ) -> u256;
}