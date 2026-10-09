//! ABI v1: POD values, no owned pointers or callbacks. Unknown integers are -1;
//! unknown temperatures are i32::MIN. All externally supplied flags are validated.
use crate::{
    calibration::{Calibration, Phase},
    controller::evaluate,
    model::*,
    schedule::{self, Occurrence},
};
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct Input {
    pub enabled: i32,
    pub limit: i32,
    pub lower: i32,
    pub thermal_enabled: i32,
    pub resume: i32,
    pub stop: i32,
    pub target: i32,
    pub soc: i32,
    pub plugged: i32,
    pub temperature: i32,
    pub holding: i32,
    pub thermal_hold: i32,
    pub capabilities: i32,
}
#[repr(C)]
#[derive(Clone, Copy, Default, Debug)]
pub struct Output {
    pub error: i32,
    pub mode: i32,
    pub charging: i32,
    pub discharge: i32,
    pub limit: i32,
    pub reset: i32,
    pub holding: i32,
    pub thermal_hold: i32,
    pub discharge_complete: i32,
    pub sensor_missing: i32,
}
fn flag(v: i32) -> Result<bool, Error> {
    match v {
        0 => Ok(false),
        1 => Ok(true),
        _ => Err(Error::InvalidConfiguration),
    }
}
fn optional(v: i32) -> Result<Option<u8>, Error> {
    if v == -1 {
        Ok(None)
    } else {
        u8::try_from(v)
            .map(Some)
            .map_err(|_| Error::InvalidConfiguration)
    }
}
fn error(e: Error) -> i32 {
    match e {
        Error::InvalidConfiguration => 1,
        Error::InvalidSnapshot => 2,
        Error::Unsupported => 3,
    }
}
#[no_mangle]
pub extern "C" fn battune_abi_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn battune_evaluate(i: Input) -> Output {
    let run = || -> Result<Evaluation, Error> {
        if i.capabilities < 0 || i.capabilities & !15 != 0 {
            return Err(Error::InvalidConfiguration);
        }
        let c = Configuration {
            enabled: flag(i.enabled)?,
            limit: u8::try_from(i.limit).map_err(|_| Error::InvalidConfiguration)?,
            sailing_lower: optional(i.lower)?,
            thermal: if flag(i.thermal_enabled)? {
                Some((i.resume, i.stop))
            } else {
                None
            },
            discharge_target: optional(i.target)?,
        };
        let s = Snapshot {
            soc: optional(i.soc)?,
            plugged: if i.plugged == -1 {
                None
            } else {
                Some(flag(i.plugged)?)
            },
            temperature: if i.temperature == i32::MIN {
                None
            } else {
                Some(i.temperature)
            },
            now: 0,
        };
        evaluate(
            c,
            s,
            State {
                holding: flag(i.holding)?,
                thermal_hold: flag(i.thermal_hold)?,
            },
            Capabilities {
                limit: i.capabilities & 1 != 0,
                charging: i.capabilities & 2 != 0,
                discharge: i.capabilities & 4 != 0,
                reset: i.capabilities & 8 != 0,
            },
        )
    };
    match run() {
        Ok(r) => Output {
            error: 0,
            mode: r.mode as i32,
            charging: r.desired.charging.map_or(-1, i32::from),
            discharge: r.desired.discharge.map_or(-1, i32::from),
            limit: r.desired.limit.map_or(-1, i32::from),
            reset: i32::from(r.desired.reset),
            holding: i32::from(r.state.holding),
            thermal_hold: i32::from(r.state.thermal_hold),
            discharge_complete: i32::from(r.discharge_complete),
            sensor_missing: i32::from(r.sensor_missing),
        },
        Err(e) => Output {
            error: error(e),
            mode: Mode::Unavailable as i32,
            charging: -1,
            discharge: -1,
            limit: -1,
            ..Output::default()
        },
    }
}
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct CalibrationValue {
    pub phase: i32,
    pub low: i32,
    pub settle: i64,
    pub started: i64,
    pub phase_started: i64,
    pub now: i64,
    pub soc: i32,
    pub plugged: i32,
    pub blocked: i32,
    pub command: i32,
    pub supported: i32,
    pub error: i32,
}
#[no_mangle]
pub extern "C" fn battune_calibration(mut i: CalibrationValue) -> CalibrationValue {
    let run = || -> Result<Calibration, Error> {
        let phase = match i.phase {
            0 => Phase::Inactive,
            1 => Phase::Charging,
            2 => Phase::Stabilizing,
            3 => Phase::Discharging,
            4 => Phase::Recharging,
            5 => Phase::Complete,
            6 => Phase::Cancelled,
            7 => Phase::Interrupted,
            _ => return Err(Error::InvalidConfiguration),
        };
        let c = Calibration {
            phase,
            started: i.started,
            phase_started: i.phase_started,
        };
        match i.command {
            1 => Calibration::start(i.now, flag(i.supported)?),
            2 => Ok(c.cancel()),
            0 => c.advance(
                Snapshot {
                    soc: optional(i.soc)?,
                    plugged: if i.plugged == -1 {
                        None
                    } else {
                        Some(flag(i.plugged)?)
                    },
                    now: i.now,
                    temperature: None,
                },
                u8::try_from(i.low).map_err(|_| Error::InvalidConfiguration)?,
                i.settle,
                flag(i.blocked)?,
            ),
            _ => Err(Error::InvalidConfiguration),
        }
    };
    match run() {
        Ok(c) => {
            i.phase = c.phase as i32;
            i.started = c.started;
            i.phase_started = c.phase_started;
            i.error = 0;
        }
        Err(e) => i.error = error(e),
    }
    i
}
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ScheduleValue {
    pub id: u32,
    pub priority: i32,
    pub age_seconds: i64,
}
/// Returns selected index, -1 if empty, -2 if malformed. At most 32 entries.
/// # Safety
/// For nonzero count, entries must point to count initialized, aligned readable
/// ScheduleValue elements for the duration of this call. No pointer is retained.
#[no_mangle]
pub unsafe extern "C" fn battune_schedule(entries: *const ScheduleValue, count: u32) -> i32 {
    if count > 32 || (count > 0 && entries.is_null()) {
        return -2;
    }
    if count == 0 {
        return -1;
    }
    // SAFETY: caller promises a valid aligned array; bounds and null checked above.
    let input = unsafe { std::slice::from_raw_parts(entries, count as usize) };
    let values: Vec<_> = input
        .iter()
        .map(|v| Occurrence {
            id: v.id,
            priority: v.priority,
            age_seconds: v.age_seconds,
        })
        .collect();
    match schedule::active_occurrence(&values) {
        Ok(Some(i)) => i as i32,
        Ok(None) => -1,
        Err(_) => -2,
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn abi_layout() {
        assert_eq!(std::mem::size_of::<Input>(), 52);
        assert_eq!(std::mem::size_of::<Output>(), 40);
        assert_eq!(std::mem::size_of::<CalibrationValue>(), 64);
        assert_eq!(std::mem::size_of::<ScheduleValue>(), 16);
    }
    #[test]
    fn reject_invalid_flags() {
        assert_eq!(
            battune_evaluate(Input {
                enabled: 2,
                ..Input::default()
            })
            .error,
            1
        );
    }
    #[test]
    fn reject_null_schedule() {
        /* SAFETY: null is explicitly allowed when count=0 and rejected otherwise. */
        unsafe {
            assert_eq!(battune_schedule(std::ptr::null(), 1), -2);
            assert_eq!(battune_schedule(std::ptr::null(), 0), -1);
        }
    }
}
