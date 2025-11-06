pub mod constants {
    pub mod interface;
}

pub mod main;

#[cfg(test)]
pub mod mocks {
    pub mod budokan_mock;
}

#[cfg(test)]
pub mod tests {
    pub mod test_integration;
}

// Re-export for tests
pub use main::{IClaim, IClaimDispatcher, IClaimDispatcherTrait, TournamentConfig};
