#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Configuration {
    pub enabled: bool,
    pub limit: u8,
    pub sailing_lower: Option<u8>,
    pub thermal: Option<(i32, i32)>, // resume, stop; milli-degrees Celsius
    pub discharge_target: Option<u8>,
}
impl Default for Configuration {
    fn default() -> Self {
        Self {
            enabled: false,
            limit: 80,
            sailing_lower: None,
            thermal: Some((35_000, 40_000)),
            discharge_target: None,
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    InvalidConfiguration,
    InvalidSnapshot,
    Unsupported,
}
impl Configuration {
    pub fn validate(self) -> Result<Self, Error> {
        if !(20..=100).contains(&self.limit)
            || self
                .sailing_lower
                .is_some_and(|v| v < 20 || v >= self.limit)
            || self
                .discharge_target
                .is_some_and(|v| !(20..=100).contains(&v))
            || self
                .thermal
                .is_some_and(|(lo, hi)| lo < 20_000 || hi > 50_000 || lo >= hi)
        {
            return Err(Error::InvalidConfiguration);
        }
        Ok(self)
    }
}
#[derive(Clone, Copy, Debug, Default)]
pub struct Snapshot {
    pub soc: Option<u8>,
    pub plugged: Option<bool>,
    pub temperature: Option<i32>,
    pub now: i64,
}
#[derive(Clone, Copy, Debug, Default)]
pub struct Capabilities {
    pub limit: bool,
    pub charging: bool,
    pub discharge: bool,
    pub reset: bool,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
#[repr(i32)]
pub enum Mode {
    #[default]
    System = 0,
    Charging = 1,
    Holding = 2,
    ThermalHold = 3,
    Discharging = 4,
    Calibration = 5,
    Unavailable = 6,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Desired {
    pub charging: Option<bool>,
    pub discharge: Option<bool>,
    pub limit: Option<u8>,
    pub reset: bool,
}
impl Desired {
    /// The caller supplies ONLY confirmed hardware state. Failed writes must never be acknowledged.
    pub fn difference(self, confirmed: Self) -> Self {
        Self {
            charging: self.charging.filter(|v| Some(*v) != confirmed.charging),
            discharge: self.discharge.filter(|v| Some(*v) != confirmed.discharge),
            limit: self.limit.filter(|v| Some(*v) != confirmed.limit),
            reset: self.reset && !confirmed.reset,
        }
    }
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct State {
    pub holding: bool,
    pub thermal_hold: bool,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Evaluation {
    pub state: State,
    pub desired: Desired,
    pub mode: Mode,
    pub discharge_complete: bool,
    pub sensor_missing: bool,
}
