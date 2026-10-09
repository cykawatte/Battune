use crate::model::{Configuration, Error};
#[derive(Clone, Copy, Debug)]
pub struct Schedule {
    pub id: u32,
    pub days: u8,
    pub minute: u16,
    pub priority: i32,
    pub configuration: Configuration,
}
/// Civil weekday is Monday=0. Latest weekly activation wins; ties use higher
/// priority then lower stable ID. Caller converts current timezone via Calendar.
pub fn active(entries: &[Schedule], weekday: u8, minute: u16) -> Result<Option<usize>, Error> {
    if weekday > 6 || minute >= 1440 {
        return Err(Error::InvalidConfiguration);
    }
    let now = i32::from(weekday) * 1440 + i32::from(minute);
    let mut best: Option<(i32, i64, u32, usize)> = None;
    for (index, e) in entries.iter().enumerate() {
        e.configuration.validate()?;
        if e.days == 0 || e.days > 127 || e.minute >= 1440 {
            return Err(Error::InvalidConfiguration);
        }
        for day in 0..7 {
            if e.days & (1 << day) == 0 {
                continue;
            }
            let age = (now - (day * 1440 + i32::from(e.minute))).rem_euclid(10080);
            let candidate = (age, -i64::from(e.priority), e.id, index);
            if best.is_none_or(|b| candidate < b) {
                best = Some(candidate);
            }
        }
    }
    Ok(best.map(|b| b.3))
}
#[cfg(test)]
mod tests {
    use super::*;
    fn e(id: u32, days: u8, minute: u16, priority: i32) -> Schedule {
        Schedule {
            id,
            days,
            minute,
            priority,
            configuration: Configuration::default(),
        }
    }
    #[test]
    fn weekly_midnight_and_priority() {
        let entries = [e(1, 1, 600, 0), e(2, 1, 600, 1), e(3, 64, 1439, 0)];
        assert_eq!(active(&entries, 0, 600), Ok(Some(1)));
        assert_eq!(active(&entries, 0, 0), Ok(Some(2)));
        assert_eq!(active(&entries, 6, 1438), Ok(Some(1)));
        assert_eq!(active(&[], 0, 0), Ok(None));
    }
    #[test]
    fn invalid_input() {
        assert!(active(&[e(1, 0, 1, 0)], 0, 0).is_err());
        assert!(active(&[], 7, 0).is_err());
    }
}

#[derive(Clone, Copy)]
pub struct Occurrence {
    pub id: u32,
    pub priority: i32,
    pub age_seconds: i64,
}
/// The platform resolves civil time (including DST) into elapsed time. Policy
/// selects latest activation, then higher priority, then lowest stable ID.
pub fn active_occurrence(entries: &[Occurrence]) -> Result<Option<usize>, Error> {
    if entries.iter().any(|e| e.age_seconds < 0) {
        return Err(Error::InvalidConfiguration);
    }
    Ok(entries
        .iter()
        .enumerate()
        .min_by_key(|(index, e)| (e.age_seconds, -i64::from(e.priority), e.id, *index))
        .map(|(index, _)| index))
}
