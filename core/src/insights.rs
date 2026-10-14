//! Pure policy for user overrides, native ceilings, time estimates and the
//! MagSafe indicator. No hardware, clock or platform knowledge.
use crate::model::{Error, Mode};

/// A temporary, user-requested deviation from the configured charge limit.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[repr(i32)]
pub enum Override {
    #[default]
    None = 0,
    /// Charge to 100% once; ends when the adapter is disconnected.
    TopUp = 1,
    /// Hold the battery at the percentage captured when the pause started.
    Pause = 2,
}

impl Override {
    pub fn from_raw(value: i32) -> Result<Self, Error> {
        match value {
            0 => Ok(Self::None),
            1 => Ok(Self::TopUp),
            2 => Ok(Self::Pause),
            _ => Err(Error::InvalidConfiguration),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Resolution {
    pub limit: u8,
    /// The override has ended and the caller should forget it.
    pub complete: bool,
}

/// Resolves the effective limit. An unknown power state never ends an override,
/// and never raises the limit for a pause.
pub fn resolve(
    configured: u8,
    kind: Override,
    paused_at: Option<u8>,
    plugged: Option<bool>,
) -> Result<Resolution, Error> {
    if !(20..=100).contains(&configured) || paused_at.is_some_and(|p| p > 100) {
        return Err(Error::InvalidConfiguration);
    }
    let unplugged = plugged == Some(false);
    Ok(match kind {
        Override::None => Resolution {
            limit: configured,
            complete: false,
        },
        Override::TopUp if unplugged => Resolution {
            limit: configured,
            complete: true,
        },
        Override::TopUp => Resolution {
            limit: 100,
            complete: false,
        },
        Override::Pause => match paused_at {
            None => Resolution {
                limit: configured,
                complete: true,
            },
            Some(_) if unplugged => Resolution {
                limit: configured,
                complete: true,
            },
            // A pause can only lower the ceiling; it never charges further.
            Some(p) => Resolution {
                limit: p.clamp(20, configured),
                complete: false,
            },
        },
    })
}

/// Smallest supported native limit at or above the request. Native limits are
/// a ceiling: rounding down would silently stop charging earlier than asked,
/// rounding up keeps adapter input enabled while still protecting the battery.
pub fn native_ceiling(requested: u8, supported: &[u8]) -> Option<u8> {
    supported
        .iter()
        .copied()
        .filter(|v| (20..=100).contains(v) && *v >= requested)
        .min()
}

#[derive(Clone, Copy, Debug, Default)]
pub struct EstimateInput {
    /// Remaining and full-charge capacity in mAh.
    pub remaining: Option<u32>,
    pub full: Option<u32>,
    /// Battery current in mA; positive while charging.
    pub current: Option<i32>,
    /// Stop point while charging, in percent.
    pub target: u8,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Estimate {
    pub minutes_to_target: Option<u32>,
    pub minutes_to_empty: Option<u32>,
}

/// Linear estimate from the instantaneous current, bounded to 48 hours. Currents
/// below 50 mA are idle noise (trickle or hold) and produce no estimate.
pub fn estimate(input: EstimateInput) -> Result<Estimate, Error> {
    if !(1..=100).contains(&input.target) {
        return Err(Error::InvalidConfiguration);
    }
    let mut result = Estimate::default();
    let (Some(remaining), Some(full), Some(current)) = (input.remaining, input.full, input.current)
    else {
        return Ok(result);
    };
    if full == 0 || remaining > full.saturating_mul(2) || current.unsigned_abs() < 50 {
        return Ok(result);
    }
    let bound = |minutes: u64| u32::try_from(minutes).ok().filter(|m| *m <= 48 * 60);
    if current > 0 {
        let goal = u64::from(full) * u64::from(input.target) / 100;
        let missing = goal.saturating_sub(u64::from(remaining));
        if missing > 0 {
            result.minutes_to_target = bound(missing * 60 / current.unsigned_abs() as u64);
        }
    } else {
        result.minutes_to_empty =
            bound(u64::from(remaining) * 60 / u64::from(current.unsigned_abs()));
    }
    Ok(result)
}

/// MagSafe indicator values accepted by the helper. `System` returns control to macOS.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[repr(i32)]
pub enum Indicator {
    #[default]
    System = 0,
    Off = 1,
    Green = 3,
    Amber = 4,
}

/// User preference for the MagSafe indicator.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[repr(i32)]
pub enum IndicatorStyle {
    #[default]
    System = 0,
    Off = 1,
    /// Amber while charging or discharging, green while holding at the limit.
    ChargeState = 2,
}

pub fn indicator(
    style: IndicatorStyle,
    mode: Mode,
    plugged: Option<bool>,
    charging: Option<bool>,
) -> Indicator {
    match style {
        IndicatorStyle::System => Indicator::System,
        IndicatorStyle::Off => Indicator::Off,
        IndicatorStyle::ChargeState => match (plugged, mode) {
            (Some(true), Mode::Discharging | Mode::Calibration) => Indicator::Amber,
            (Some(true), Mode::Holding) => Indicator::Green,
            (Some(true), _) if charging == Some(true) => Indicator::Amber,
            (Some(true), _) if charging == Some(false) => Indicator::Green,
            // Unknown or no power: let macOS decide; never guess a color.
            _ => Indicator::System,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn top_up_runs_until_unplugged() {
        let on = resolve(80, Override::TopUp, None, Some(true)).unwrap();
        assert_eq!(on.limit, 100);
        assert!(!on.complete);
        assert!(!resolve(80, Override::TopUp, None, None).unwrap().complete);
        let off = resolve(80, Override::TopUp, None, Some(false)).unwrap();
        assert_eq!(
            off,
            Resolution {
                limit: 80,
                complete: true
            }
        );
    }

    #[test]
    fn pause_never_raises_the_limit() {
        for configured in 20..=100u8 {
            for soc in 0..=100u8 {
                let r = resolve(configured, Override::Pause, Some(soc), Some(true)).unwrap();
                assert!(r.limit <= configured);
                assert!(r.limit >= 20);
                assert!(!r.complete);
            }
        }
        assert!(
            resolve(80, Override::Pause, None, Some(true))
                .unwrap()
                .complete
        );
        assert!(
            resolve(80, Override::Pause, Some(60), Some(false))
                .unwrap()
                .complete
        );
    }

    #[test]
    fn invalid_inputs_are_rejected() {
        assert!(resolve(19, Override::None, None, None).is_err());
        assert!(resolve(101, Override::None, None, None).is_err());
        assert!(resolve(80, Override::Pause, Some(101), None).is_err());
        assert!(Override::from_raw(3).is_err());
        assert!(estimate(EstimateInput::default()).is_err());
    }

    #[test]
    fn native_ceiling_rounds_up() {
        let supported = [80, 85, 90, 95, 100];
        assert_eq!(native_ceiling(77, &supported), Some(80));
        assert_eq!(native_ceiling(80, &supported), Some(80));
        assert_eq!(native_ceiling(81, &supported), Some(85));
        assert_eq!(native_ceiling(100, &supported), Some(100));
        assert_eq!(native_ceiling(50, &[]), None);
        assert_eq!(native_ceiling(50, &[10, 101]), None);
    }

    #[test]
    fn estimates_are_bounded_and_signed() {
        let charging = estimate(EstimateInput {
            remaining: Some(2000),
            full: Some(4000),
            current: Some(2000),
            target: 80,
        })
        .unwrap();
        assert_eq!(charging.minutes_to_target, Some(36));
        assert_eq!(charging.minutes_to_empty, None);
        let draining = estimate(EstimateInput {
            remaining: Some(3000),
            full: Some(4000),
            current: Some(-1000),
            target: 80,
        })
        .unwrap();
        assert_eq!(draining.minutes_to_empty, Some(180));
        let idle = estimate(EstimateInput {
            remaining: Some(3000),
            full: Some(4000),
            current: Some(10),
            target: 80,
        })
        .unwrap();
        assert_eq!(idle, Estimate::default());
        let reached = estimate(EstimateInput {
            remaining: Some(3300),
            full: Some(4000),
            current: Some(500),
            target: 80,
        })
        .unwrap();
        assert_eq!(reached.minutes_to_target, None);
        let slow = estimate(EstimateInput {
            remaining: Some(4000),
            full: Some(4000),
            current: Some(-50),
            target: 80,
        })
        .unwrap();
        assert_eq!(slow.minutes_to_empty, None);
    }

    #[test]
    fn indicator_follows_state_without_guessing() {
        use IndicatorStyle::*;
        assert_eq!(
            indicator(System, Mode::Holding, Some(true), Some(false)),
            Indicator::System
        );
        assert_eq!(
            indicator(Off, Mode::Charging, Some(true), Some(true)),
            Indicator::Off
        );
        assert_eq!(
            indicator(ChargeState, Mode::Holding, Some(true), Some(false)),
            Indicator::Green
        );
        assert_eq!(
            indicator(ChargeState, Mode::Discharging, Some(true), Some(false)),
            Indicator::Amber
        );
        assert_eq!(
            indicator(ChargeState, Mode::System, Some(true), Some(true)),
            Indicator::Amber
        );
        assert_eq!(
            indicator(ChargeState, Mode::Charging, None, Some(true)),
            Indicator::System
        );
        assert_eq!(
            indicator(ChargeState, Mode::Charging, Some(true), None),
            Indicator::System
        );
    }
}
