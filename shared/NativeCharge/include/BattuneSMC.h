#ifndef BATTUNE_SMC_H
#define BATTUNE_SMC_H
#include <stdint.h>
typedef struct { uint32_t io_result; uint32_t size; uint32_t type; uint8_t smc_result; uint8_t bytes[32]; } BTKeyProbe;
// Fixed diagnostic key IDs only. No arbitrary key or data crosses IPC.
const char *bt_smc_key_name(int key);
BTKeyProbe bt_smc_probe(int key);
// Root-only, fixed adapter operation; validates metadata, value and readback.
uint32_t bt_smc_adapter(int enabled);
// Root-only MagSafe indicator write: 0 system, 1 off, 3 green, 4 amber; validated metadata.
uint32_t bt_smc_indicator(int value);
// 0 = open, 1 = closed, -1 = unavailable. Read-only IORegistry query.
int bt_clamshell_closed(void);
#endif
