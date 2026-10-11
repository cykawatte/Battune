#ifndef BATTUNE_NATIVE_CHARGE_H
#define BATTUNE_NATIVE_CHARGE_H
#include <stdint.h>
// Returns 0 on success, 3 if unavailable, 5 for a platform error. No arbitrary selectors.
int bt_native_read(int *limit, int *enabled, int *limits, int capacity, int *count);
int bt_native_set(int limit);
int bt_native_disable(void);
#endif
