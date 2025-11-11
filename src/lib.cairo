pub mod constants {
    pub mod identifier;
    pub mod interface;
    pub mod units;
}

pub mod main;

#[cfg(test)]
pub mod mocks {
    pub mod budokan_mock;
    pub mod erc20_mock;
}

#[cfg(test)]
pub mod tests {
    pub mod test_integration;
}

// Re-export for tests
pub use main::{
    IClaim, IClaimDispatcher, IClaimDispatcherTrait, TournamentConfig, LeafDataWithExtraData
};
