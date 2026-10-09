use crate::model::{Error, Snapshot};
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[repr(i32)]
pub enum Phase {
    #[default]
    Inactive = 0,
    Charging = 1,
    Stabilizing = 2,
    Discharging = 3,
    Recharging = 4,
    Complete = 5,
    Cancelled = 6,
    Interrupted = 7,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Calibration {
    pub phase: Phase,
    pub started: i64,
    pub phase_started: i64,
}
impl Calibration {
    pub fn start(now: i64, supported: bool) -> Result<Self, Error> {
        if !supported {
            return Err(Error::Unsupported);
        }
        Ok(Self {
            phase: Phase::Charging,
            started: now,
            phase_started: now,
        })
    }
    pub fn active(self) -> bool {
        matches!(
            self.phase,
            Phase::Charging | Phase::Stabilizing | Phase::Discharging | Phase::Recharging
        )
    }
    pub fn cancel(mut self) -> Self {
        self.phase = Phase::Cancelled;
        self
    }
    pub fn advance(
        mut self,
        snapshot: Snapshot,
        low: u8,
        settle_seconds: i64,
        thermally_blocked: bool,
    ) -> Result<Self, Error> {
        if !(20..=50).contains(&low) || !(0..=7200).contains(&settle_seconds) {
            return Err(Error::InvalidConfiguration);
        }
        if !self.active() {
            return Ok(self);
        }
        // Wall-clock rollback, unplug and the bounded overall duration abort safely.
        if snapshot.now < self.phase_started
            || snapshot.now - self.started > 172_800
            || snapshot.plugged != Some(true)
        {
            self.phase = Phase::Interrupted;
            return Ok(self);
        }
        if thermally_blocked {
            return Ok(self);
        }
        let phase = match (self.phase, snapshot.soc) {
            (Phase::Charging, Some(100)) => Phase::Stabilizing,
            (Phase::Stabilizing, _) if snapshot.now - self.phase_started >= settle_seconds => {
                Phase::Discharging
            }
            (Phase::Discharging, Some(soc)) if soc <= low => Phase::Recharging,
            (Phase::Recharging, Some(100)) => Phase::Complete,
            _ => self.phase,
        };
        if phase != self.phase {
            self.phase = phase;
            self.phase_started = snapshot.now;
        }
        Ok(self)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn s(soc: u8, now: i64) -> Snapshot {
        Snapshot {
            soc: Some(soc),
            plugged: Some(true),
            now,
            ..Snapshot::default()
        }
    }
    #[test]
    fn full_workflow() {
        let c = Calibration::start(0, true).unwrap();
        let c = c.advance(s(100, 10), 20, 60, false).unwrap();
        assert_eq!(c.phase, Phase::Stabilizing);
        assert_eq!(
            c.advance(s(100, 69), 20, 60, false).unwrap().phase,
            Phase::Stabilizing
        );
        let c = c.advance(s(100, 70), 20, 60, false).unwrap();
        assert_eq!(c.phase, Phase::Discharging);
        let c = c.advance(s(20, 500), 20, 60, false).unwrap();
        assert_eq!(c.phase, Phase::Recharging);
        assert_eq!(
            c.advance(s(100, 1000), 20, 60, false).unwrap().phase,
            Phase::Complete
        );
    }
    #[test]
    fn safety_and_cancel() {
        assert!(Calibration::start(0, false).is_err());
        let c = Calibration::start(100, true).unwrap();
        assert_eq!(c.cancel().phase, Phase::Cancelled);
        assert_eq!(
            c.advance(s(100, 101), 20, 0, true).unwrap().phase,
            Phase::Charging
        );
        assert_eq!(
            c.advance(s(80, 99), 20, 0, false).unwrap().phase,
            Phase::Interrupted
        );
        assert_eq!(
            c.advance(s(80, 200_000), 20, 0, false).unwrap().phase,
            Phase::Interrupted
        );
        assert_eq!(
            c.advance(Snapshot::default(), 20, 0, false).unwrap().phase,
            Phase::Interrupted
        );
    }
}
