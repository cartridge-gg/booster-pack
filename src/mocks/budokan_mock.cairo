use starknet::ContractAddress;
use booster_pack_devconnect::constants::interface::QualificationProof;

#[starknet::interface]
pub trait IBudokanMock<TContractState> {
    fn enter_tournament(
        ref self: TContractState,
        tournament_id: u64,
        player_name: felt252,
        player_address: ContractAddress,
        qualification: Option<QualificationProof>,
    ) -> (u64, u32);
    fn get_tournament_entry_count(self: @TContractState, tournament_id: u64) -> u32;
    fn get_total_entries(self: @TContractState) -> u64;
    fn set_tournament_allowlist(
        ref self: TContractState, tournament_id: u64, allowed_address: ContractAddress
    );
}

#[starknet::contract]
pub mod BudokanMock {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess
    };
    use booster_pack_devconnect::constants::interface::QualificationProof;

    #[storage]
    struct Storage {
        next_token_id: u64,
        tournament_entry_counts: Map<u64, u32>,
        tournament_allowlists: Map<u64, ContractAddress>,
        total_entries: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        TournamentEntered: TournamentEntered,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TournamentEntered {
        pub tournament_id: u64,
        pub player_address: ContractAddress,
        pub player_name: felt252,
        pub game_token_id: u64,
        pub entry_number: u32,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.next_token_id.write(1);
        self.total_entries.write(0);
    }

    #[abi(embed_v0)]
    impl BudokanMockImpl of super::IBudokanMock<ContractState> {
        fn enter_tournament(
            ref self: ContractState,
            tournament_id: u64,
            player_name: felt252,
            player_address: ContractAddress,
            qualification: Option<QualificationProof>,
        ) -> (u64, u32) {
            let caller = get_caller_address();

            // Validate allowlist if qualification proof is provided
            if let Option::Some(proof) = qualification {
                match proof {
                    QualificationProof::Allowlist(allowed_addr) => {
                        let configured_allowlist = self
                            .tournament_allowlists
                            .entry(tournament_id)
                            .read();
                        assert(caller == configured_allowlist, 'Not on allowlist');
                        assert(allowed_addr == caller, 'Invalid allowlist proof');
                    },
                    _ => { panic!("Only allowlist supported"); }
                }
            }

            // Get current token ID and increment
            let token_id = self.next_token_id.read();
            self.next_token_id.write(token_id + 1);

            // Get current entry number for this tournament and increment
            let entry_number = self.tournament_entry_counts.entry(tournament_id).read() + 1;
            self.tournament_entry_counts.entry(tournament_id).write(entry_number);

            // Increment total entries
            let total = self.total_entries.read();
            self.total_entries.write(total + 1);

            // Emit event
            self
                .emit(
                    TournamentEntered {
                        tournament_id, player_address, player_name, game_token_id: token_id, entry_number
                    }
                );

            (token_id, entry_number)
        }

        fn get_tournament_entry_count(self: @ContractState, tournament_id: u64) -> u32 {
            self.tournament_entry_counts.entry(tournament_id).read()
        }

        fn get_total_entries(self: @ContractState) -> u64 {
            self.total_entries.read()
        }

        fn set_tournament_allowlist(
            ref self: ContractState, tournament_id: u64, allowed_address: ContractAddress
        ) {
            self.tournament_allowlists.entry(tournament_id).write(allowed_address);
        }
    }
}
