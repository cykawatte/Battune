#ifndef BATTUNE_CORE_H
#define BATTUNE_CORE_H
#include <stdint.h>
// ABI 2. Values only, except the borrowed schedule array. No retained pointers.
// Unknown SOC/power/lower/target = -1; unknown temperature = INT32_MIN.
typedef struct {
    int32_t enabled, limit, lower, thermal_enabled, resume, stop, target, soc;
    int32_t plugged, temperature, holding, thermal_hold, capabilities;
} BattuneInput;
typedef struct {
    int32_t error, mode, charging, discharge, limit, reset, holding, thermal_hold;
    int32_t discharge_complete, sensor_missing;
} BattuneOutput;
typedef struct {
    int32_t phase, low;
    int64_t settle, started, phase_started, now;
    int32_t soc, plugged, blocked, command, supported, error;
} BattuneCalibration;
typedef struct { uint32_t id; int32_t priority; int64_t age_seconds; } BattuneSchedule;
// kind: 0 none, 1 top-up until unplugged, 2 pause at paused_at. Outputs: limit, complete, error.
typedef struct { int32_t configured, kind, paused_at, plugged, limit, complete, error; } BattuneOverride;
// Capacities in mAh (-1 unknown), current in mA (INT32_MIN unknown). Outputs in minutes or -1.
typedef struct { int32_t remaining, full, current, target, to_target, to_empty, error; } BattuneEstimate;
uint32_t battune_abi_version(void);
BattuneOutput battune_evaluate(BattuneInput input);
BattuneCalibration battune_calibration(BattuneCalibration input);
int32_t battune_schedule(const BattuneSchedule *entries, uint32_t count);
BattuneOverride battune_override(BattuneOverride input);
BattuneEstimate battune_estimate(BattuneEstimate input);
int32_t battune_native_ceiling(int32_t requested, const int32_t *values, uint32_t count);
int32_t battune_indicator(int32_t style, int32_t mode, int32_t plugged, int32_t charging);
_Static_assert(sizeof(BattuneInput) == 52, "Input ABI");
_Static_assert(sizeof(BattuneOutput) == 40, "Output ABI");
_Static_assert(sizeof(BattuneCalibration) == 64, "Calibration ABI");
_Static_assert(sizeof(BattuneOverride) == 28, "Override ABI");
_Static_assert(sizeof(BattuneEstimate) == 28, "Estimate ABI");
#endif
