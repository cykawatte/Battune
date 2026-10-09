use battune_core::{controller::evaluate, model::*};
use std::{hint::black_box, time::Instant};
fn main() {
    let config = Configuration {
        enabled: true,
        ..Configuration::default()
    };
    let caps = Capabilities {
        limit: true,
        charging: true,
        discharge: true,
        reset: true,
    };
    let start = Instant::now();
    let mut state = State::default();
    for i in 0..1_000_000 {
        let snapshot = Snapshot {
            soc: Some((i % 101) as u8),
            plugged: Some(true),
            temperature: Some(30_000),
            now: i,
        };
        let result = evaluate(
            black_box(config),
            black_box(snapshot),
            black_box(state),
            black_box(caps),
        )
        .expect("valid benchmark fixture");
        state = black_box(result.state);
    }
    println!("1,000,000 deterministic evaluations: {:?}", start.elapsed());
}
