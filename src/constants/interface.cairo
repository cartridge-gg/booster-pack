use starknet::ContractAddress;

#[derive(Drop, Serde, Copy)]
pub enum QualificationProof {
    Tournament: u64,
    Token: ContractAddress,
    Allowlist: ContractAddress,
    Extension: ContractAddress,
}

#[starknet::interface]
pub trait IBudokan<T> {
    fn enter_tournament(
        ref self: T,
        tournament_id: u64,
        player_name: felt252,
        player_address: ContractAddress,
        qualification: Option<QualificationProof>,
    ) -> (u64, u32);
}
