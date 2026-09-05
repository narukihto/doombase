use predictive_mev_bot::{CausalCollapseSystem, QuantumNode, MachineMetric, Direction, generate_astronomical_number};
use num_bigint::BigUint;
use std::time::{Instant, Duration};

#[cfg(test)]
mod strict_mev_tests {
    use super::*;

    #[test]
    fn test_astronomical_scaling_and_memory_absorption() {
        let start_time = Instant::now();
        let mut nodes = Vec::new();

        for i in 1..=100_000 {
            nodes.push(QuantumNode {
                id: i,
                energy_scale: generate_astronomical_number(15 + (i % 10)),
                frequency: 0.01,
            });
        }

        let system = CausalCollapseSystem::new(nodes);
        let path = system.execute_collapse();
        let duration = start_time.elapsed();

        assert!(!path.is_empty());
        assert!(duration.as_secs() < 5);
        println!("✅ Test 1 Passed: 100k Pools processed in {:?}", duration);
    }

    #[test]
    fn test_shortest_path_and_circuit_breaker() {
        let nodes = vec![
            QuantumNode { id: 1, energy_scale: generate_astronomical_number(20), frequency: 0.01 },
            QuantumNode { id: 2, energy_scale: generate_astronomical_number(18), frequency: 0.50 }, 
            QuantumNode { id: 3, energy_scale: generate_astronomical_number(15), frequency: 0.01 }, 
        ];

        let mut system = CausalCollapseSystem::new(nodes);
        system.threshold_limit = 0.10; 

        let path = system.execute_collapse();

        assert!(path.contains(&1));
        assert!(!path.contains(&2)); 
        assert!(path.contains(&3));
        println!("✅ Test 2 Passed: Circuit breaker isolated volatile pools perfectly.");
    }

    #[test]
    fn test_worst_case_scenario_noise() {
        let mut radar = MachineMetric::new();
        let fast_prices = vec![100.0, 100.005, 99.990, 99.985, 100.010];
        
        let mut peak_captured = false;
        let mut bottom_captured = false;

        for price in fast_prices {
            let (direction, _) = radar.update_and_predict(price);
            if direction == Direction::Peak { peak_captured = true; }
            if direction == Direction::Bottom { bottom_captured = true; }
        }

        assert!(peak_captured);
        assert!(bottom_captured);
        println!("✅ Test 3 Passed: Predictive Radar remained operational.");
    }

    #[test]
    fn test_discrete_discontinuous_cryptographic_break() {
        let nodes = vec![
            QuantumNode { id: 101, energy_scale: generate_astronomical_number(60), frequency: 0.11 },
            QuantumNode { id: 102, energy_scale: generate_astronomical_number(58), frequency: 0.89 }, 
            QuantumNode { id: 103, energy_scale: generate_astronomical_number(55), frequency: 0.12 },
        ];

        let mut system = CausalCollapseSystem::new(nodes);
        system.threshold_limit = 0.05; 

        let path = system.execute_collapse();

        assert!(path.contains(&101));
        assert!(path.contains(&103));
        println!("✅ Test 4 Passed: Discontinuous network break handled safely.");
    }
}
