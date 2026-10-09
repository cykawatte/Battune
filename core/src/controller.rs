use crate::model::*;

pub fn evaluate(
    config: Configuration,
    snapshot: Snapshot,
    previous: State,
    caps: Capabilities,
) -> Result<Evaluation, Error> {
    let c = config.validate()?;
    if snapshot.soc.is_some_and(|s| s > 100)
        || snapshot
            .temperature
            .is_some_and(|t| !(-20_000..=100_000).contains(&t))
    {
        return Err(Error::InvalidSnapshot);
    }
    let mut result = Evaluation {
        state: previous,
        desired: Desired::default(),
        mode: Mode::System,
        discharge_complete: false,
        sensor_missing: false,
    };
    if !c.enabled {
        result.state = State::default();
        result.desired.reset = caps.reset;
        return Ok(result);
    }
    // Missing power/SOC information never authorizes charging or continued forced discharge.
    let (soc, plugged) = match (snapshot.soc, snapshot.plugged) {
        (Some(s), Some(p)) => (s, p),
        _ => {
            result.mode = Mode::Unavailable;
            result.sensor_missing = true;
            result.desired.reset = caps.reset;
            return Ok(result);
        }
    };
    if !plugged {
        result.state = State::default();
        result.desired.reset = caps.reset;
        result.discharge_complete = c.discharge_target.is_some();
        return Ok(result);
    }
    if !(caps.limit || caps.charging) {
        result.mode = Mode::Unavailable;
        return Ok(result);
    }
    result.desired.discharge = caps.discharge.then_some(false);
    if let Some((resume, stop)) = c.thermal {
        match snapshot.temperature {
            Some(t) if t >= stop => result.state.thermal_hold = true,
            Some(t) if t <= resume => result.state.thermal_hold = false,
            None => {
                result.sensor_missing = true;
                result.state.thermal_hold = true;
            }
            _ => {}
        }
        if result.state.thermal_hold {
            result.mode = if caps.charging {
                Mode::ThermalHold
            } else {
                Mode::Unavailable
            };
            result.desired.charging = caps.charging.then_some(false);
            // A hardware limit alone cannot guarantee a thermal stop.
            return Ok(result);
        }
    } else {
        result.state.thermal_hold = false;
    }
    if let Some(target) = c.discharge_target {
        if !caps.discharge {
            return Err(Error::Unsupported);
        }
        if soc > target {
            result.desired.charging = caps.charging.then_some(false);
            result.desired.discharge = Some(true);
            result.mode = Mode::Discharging;
            return Ok(result);
        }
        result.discharge_complete = true;
    }
    let lower = c.sailing_lower.unwrap_or(c.limit.saturating_sub(1));
    if soc >= c.limit {
        result.state.holding = true;
    } else if soc <= lower {
        result.state.holding = false;
    }
    result.mode = if result.state.holding {
        Mode::Holding
    } else {
        Mode::Charging
    };
    result.desired.limit = caps.limit.then_some(c.limit);
    // Direct limits are preferred. Sailing additionally needs a charging gate.
    if caps.charging {
        result.desired.charging = Some(!result.state.holding);
    }
    if c.sailing_lower.is_some() && !caps.charging {
        return Err(Error::Unsupported);
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn config() -> Configuration {
        Configuration {
            enabled: true,
            thermal: None,
            ..Configuration::default()
        }
    }
    fn snap(soc: u8) -> Snapshot {
        Snapshot {
            soc: Some(soc),
            plugged: Some(true),
            ..Snapshot::default()
        }
    }
    fn caps() -> Capabilities {
        Capabilities {
            limit: true,
            charging: true,
            discharge: true,
            reset: true,
        }
    }
    #[test]
    fn boundaries_and_idempotency() {
        for limit in 20..=100 {
            let c = Configuration { limit, ..config() };
            let a = evaluate(c, snap(limit), State::default(), caps()).unwrap();
            assert_eq!(a.mode, Mode::Holding);
            assert_eq!(a.desired.difference(a.desired), Desired::default());
            assert_eq!(
                evaluate(c, snap(limit - 1), a.state, caps()).unwrap().mode,
                Mode::Charging
            );
        }
    }
    #[test]
    fn sailing_preserves_band() {
        let c = Configuration {
            sailing_lower: Some(75),
            ..config()
        };
        let held = evaluate(c, snap(80), State::default(), caps()).unwrap();
        assert_eq!(
            evaluate(c, snap(78), held.state, caps()).unwrap().mode,
            Mode::Holding
        );
        let charging = evaluate(c, snap(75), held.state, caps()).unwrap();
        assert_eq!(charging.mode, Mode::Charging);
        assert_eq!(
            evaluate(c, snap(79), charging.state, caps()).unwrap().mode,
            Mode::Charging
        );
    }
    #[test]
    fn thermal_priority_hysteresis_and_missing() {
        let c = Configuration {
            thermal: Some((35_000, 40_000)),
            discharge_target: Some(30),
            ..config()
        };
        let mut s = snap(85);
        s.temperature = Some(40_000);
        let hot = evaluate(c, s, State::default(), caps()).unwrap();
        assert_eq!(hot.mode, Mode::ThermalHold);
        assert_eq!(hot.desired.discharge, Some(false));
        s.temperature = Some(38_000);
        assert_eq!(
            evaluate(c, s, hot.state, caps()).unwrap().mode,
            Mode::ThermalHold
        );
        s.temperature = Some(35_000);
        assert_eq!(
            evaluate(c, s, hot.state, caps()).unwrap().mode,
            Mode::Discharging
        );
        s.temperature = None;
        assert!(
            evaluate(c, s, State::default(), caps())
                .unwrap()
                .sensor_missing
        );
    }
    #[test]
    fn discharge_target_and_disconnect() {
        let c = Configuration {
            discharge_target: Some(75),
            ..config()
        };
        assert_eq!(
            evaluate(c, snap(96), State::default(), caps())
                .unwrap()
                .desired
                .discharge,
            Some(true)
        );
        assert!(
            evaluate(c, snap(75), State::default(), caps())
                .unwrap()
                .discharge_complete
        );
        let s = Snapshot {
            plugged: Some(false),
            ..snap(80)
        };
        assert!(
            evaluate(c, s, State::default(), caps())
                .unwrap()
                .desired
                .reset
        );
    }
    #[test]
    fn invalid_and_unknown() {
        for limit in [0, 19, 101, 255] {
            assert!(Configuration { limit, ..config() }.validate().is_err());
        }
        assert!(Configuration {
            sailing_lower: Some(80),
            ..config()
        }
        .validate()
        .is_err());
        assert!(Configuration {
            thermal: Some((40_000, 40_000)),
            ..config()
        }
        .validate()
        .is_err());
        let e = evaluate(config(), Snapshot::default(), State::default(), caps()).unwrap();
        assert_eq!(e.mode, Mode::Unavailable);
        assert!(e.desired.reset);
        assert_eq!(
            evaluate(config(), snap(101), State::default(), caps()),
            Err(Error::InvalidSnapshot)
        );
    }
    #[test]
    fn capabilities_never_fabricate_control() {
        assert_eq!(
            evaluate(
                config(),
                snap(50),
                State::default(),
                Capabilities::default()
            )
            .unwrap()
            .mode,
            Mode::Unavailable
        );
        let direct = Capabilities {
            limit: true,
            ..Capabilities::default()
        };
        assert_eq!(
            evaluate(config(), snap(50), State::default(), direct)
                .unwrap()
                .desired
                .charging,
            None
        );
        assert_eq!(
            evaluate(
                Configuration {
                    sailing_lower: Some(75),
                    ..config()
                },
                snap(50),
                State::default(),
                direct
            ),
            Err(Error::Unsupported)
        );
    }
    #[test]
    fn disabled_resets() {
        assert!(
            evaluate(Configuration::default(), snap(50), State::default(), caps())
                .unwrap()
                .desired
                .reset
        );
    }
    #[test]
    fn exhaustive_sailing_invariants() {
        for lower in 20..99 {
            for upper in (lower + 1)..=100 {
                for soc in 0..=100 {
                    for holding in [true, false] {
                        let c = Configuration {
                            limit: upper,
                            sailing_lower: Some(lower),
                            ..config()
                        };
                        let r = evaluate(
                            c,
                            snap(soc),
                            State {
                                holding,
                                thermal_hold: false,
                            },
                            caps(),
                        )
                        .unwrap();
                        assert_eq!(
                            r.state.holding,
                            if soc >= upper {
                                true
                            } else if soc <= lower {
                                false
                            } else {
                                holding
                            }
                        );
                    }
                }
            }
        }
    }
}
