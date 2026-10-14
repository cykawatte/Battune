#include "BattuneSMC.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>

// AppleSMC user-client wire ABI (80 bytes, payload at byte 48).
// Layout/protocol facts independently implemented from public interface research.
typedef struct {
    uint32_t key;
    uint8_t version[6];
    uint16_t padding;
    uint16_t power_version, power_length;
    uint32_t cpu_limit, gpu_limit, memory_limit;
    uint32_t size, type;
    uint8_t attributes, reserved[3];
    uint8_t result, status, command, reserved2;
    uint32_t index;
    uint8_t bytes[32];
} Packet;
_Static_assert(sizeof(Packet) == 80, "SMC packet layout");
_Static_assert(offsetof(Packet, bytes) == 48, "SMC payload layout");
static const char *keys[] = {"CHTE", "CHIE", "bfF0", "bfD0", "bfE0", "CH0B", "CH0C", "CH0I", "CH0J", "AC-W", "TB0T", "B0AC", "B0AV", "ACLC"};
#define KEY_COUNT 14
const char *bt_smc_key_name(int key) { return key >= 0 && key < KEY_COUNT ? keys[key] : "invalid"; }
static uint32_t fourcc(const char *s) { return (uint32_t)s[0]<<24 | (uint32_t)s[1]<<16 | (uint32_t)s[2]<<8 | (uint32_t)s[3]; }
static kern_return_t connect_smc(io_connect_t *connection) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return kIOReturnNotFound;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return result;
}
static kern_return_t call(io_connect_t connection, Packet *input, Packet *output) {
    size_t size = sizeof(*output);
    memset(output, 0, size);
    kern_return_t result = IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &size);
    if (result == KERN_SUCCESS && size != sizeof(*output)) return kIOReturnBadArgument;
    return result;
}
static BTKeyProbe probe(io_connect_t connection, int key) {
    BTKeyProbe probe = {0};
    if (key < 0 || key >= KEY_COUNT) { probe.io_result = kIOReturnBadArgument; return probe; }
    Packet input = {0}, output = {0};
    input.key = fourcc(keys[key]); input.command = 9;
    probe.io_result = call(connection, &input, &output); probe.smc_result = output.result;
    probe.size = output.size; probe.type = output.type;
    if (probe.io_result || probe.smc_result || probe.size == 0 || probe.size > 32) return probe;
    input.command = 5; input.size = probe.size;
    probe.io_result = call(connection, &input, &output); probe.smc_result = output.result;
    if (!probe.io_result && !probe.smc_result) memcpy(probe.bytes, output.bytes, probe.size);
    return probe;
}
BTKeyProbe bt_smc_probe(int key) {
    BTKeyProbe value = {0}; io_connect_t connection = 0;
    value.io_result = connect_smc(&connection);
    if (!value.io_result) { value = probe(connection, key); IOServiceClose(connection); }
    return value;
}
int bt_clamshell_closed(void) {
    io_service_t root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if (!root) return -1;
    CFTypeRef value = IORegistryEntryCreateCFProperty(root, CFSTR("AppleClamshellState"), kCFAllocatorDefault, 0);
    IOObjectRelease(root);
    int result = -1;
    if (value && CFGetTypeID(value) == CFBooleanGetTypeID()) result = CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
    if (value) CFRelease(value);
    return result;
}
uint32_t bt_smc_adapter(int enabled) {
    if (geteuid() != 0) return kIOReturnNotPrivileged;
    if (enabled != 0 && enabled != 1) return kIOReturnBadArgument;
    // Cutting AC can immediately suspend a docked Mac with its lid closed.
    // Check again at the write boundary; restoring AC is always allowed.
    if (!enabled && bt_clamshell_closed() != 0) return kIOReturnNotPermitted;
    io_connect_t connection = 0;
    kern_return_t result = connect_smc(&connection);
    if (result) return result;
    // CHIE is the observed adapter gate on this firmware. Other layouts fail closed.
    BTKeyProbe current = probe(connection, 1);
    if (current.io_result || current.smc_result || current.size != 1 ||
        (current.type != fourcc("ui8 ") && current.type != fourcc("hex_")) || (current.bytes[0] != 0 && current.bytes[0] != 8)) {
        IOServiceClose(connection); return current.io_result ? current.io_result : kIOReturnUnsupported;
    }
    uint8_t wanted = enabled ? 0 : 8;
    if (current.bytes[0] != wanted) {
        Packet input = {0}, output = {0}; input.key = fourcc("CHIE"); input.command = 6;
        input.size = 1; input.bytes[0] = wanted;
        result = call(connection, &input, &output);
        if (!result && output.result) result = kIOReturnNotPermitted;
        if (!result) {
            BTKeyProbe readback = probe(connection, 1);
            if (readback.io_result || readback.smc_result || readback.size != 1 || readback.bytes[0] != wanted)
                result = kIOReturnError;
        }
    }
    IOServiceClose(connection); return result;
}

uint32_t bt_smc_indicator(int value) {
    if (geteuid() != 0) return kIOReturnNotPrivileged;
    // 0 returns the LED to macOS; 1 off; 3 green; 4 amber. Nothing else is written.
    if (value != 0 && value != 1 && value != 3 && value != 4) return kIOReturnBadArgument;
    io_connect_t connection = 0;
    kern_return_t result = connect_smc(&connection);
    if (result) return result;
    BTKeyProbe current = probe(connection, 13);
    if (current.io_result || current.smc_result || current.size != 1 || current.type != fourcc("ui8 ")) {
        IOServiceClose(connection); return current.io_result ? current.io_result : kIOReturnUnsupported;
    }
    if (current.bytes[0] != value) {
        Packet input = {0}, output = {0}; input.key = fourcc("ACLC"); input.command = 6;
        input.size = 1; input.bytes[0] = (uint8_t)value;
        result = call(connection, &input, &output);
        if (!result && output.result) result = kIOReturnNotPermitted;
        // macOS replaces 0 with its own colour, so only explicit colours are read back.
        if (!result && value != 0) {
            BTKeyProbe readback = probe(connection, 13);
            if (readback.io_result || readback.smc_result || readback.size != 1 || readback.bytes[0] != value)
                result = kIOReturnError;
        }
    }
    IOServiceClose(connection); return result;
}
