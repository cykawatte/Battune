#ifndef BATTUNE_SMC_H
#define BATTUNE_SMC_H
#include <stdint.h>
typedef struct { uint32_t io_result; uint32_t size; uint32_t type; uint8_t smc_result; uint8_t bytes[32]; } BTKeyProbe;
// Fixed diagnostic key IDs only. No arbitrary key or data crosses IPC.
const char *bt_smc_key_name(int key);
BTKeyProbe bt_smc_probe(int key);
// Root-only, fixed adapter operation; validates metadata, value and readback.
uint32_t bt_smc_adapter(int enabled);
#endif
