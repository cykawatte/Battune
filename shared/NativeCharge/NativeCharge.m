#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "NativeCharge.h"

// PowerUI is private and optional. Never link against it or assume an ABI after
// an OS update: inspect every method signature before invoking the interface.
@protocol BTChargeClient
- (id)initWithClientName:(NSString *)name;
- (BOOL)isMCLSupported;
- (unsigned char)getMCLLimitWithError:(NSError **)error;
- (unsigned long long)isMCLCurrentlyEnabled:(NSError **)error;
- (NSArray *)availableChargeLimitsWithError:(NSError **)error;
- (BOOL)setMCLLimit:(unsigned char)limit error:(NSError **)error;
- (BOOL)disableMCL:(NSError **)error;
@end

static BOOL signature(id object, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    NSMethodSignature *s = [object methodSignatureForSelector:selector];
    if (!s || strcmp(s.methodReturnType, result) || s.numberOfArguments != arguments.count + 2) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        if (strcmp([s getArgumentTypeAtIndex:i + 2], arguments[i].UTF8String)) return NO;
    }
    return YES;
}

static id<BTChargeClient> createClient(void) {
    void *framework = dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_LOCAL | RTLD_LAZY);
    if (!framework) return nil;
    Class type = NSClassFromString(@"PowerUISmartChargeClient");
    if (!type) return nil;
    id object = [type alloc];
    if (!signature(object, @selector(initWithClientName:), "@", @[@"@"])) {
        return nil;
    }
    id<BTChargeClient> client = [object initWithClientName:@"Battune"];
    BOOL valid = signature(client, @selector(isMCLSupported), "B", @[])
        && signature(client, @selector(getMCLLimitWithError:), "C", @[@"^@"])
        && signature(client, @selector(isMCLCurrentlyEnabled:), "Q", @[@"^@"])
        && signature(client, @selector(availableChargeLimitsWithError:), "@", @[@"^@"])
        && signature(client, @selector(setMCLLimit:error:), "B", @[@"C", @"^@"])
        && signature(client, @selector(disableMCL:), "B", @[@"^@"]);
    if (!valid) return nil;
    return client;
}

// One validated client per process. Creating a client per call set up a fresh
// connection to the power daemon every minute; reuse is cheaper and equivalent.
// A failed lookup is retried on the next call instead of being cached.
static id<BTChargeClient> makeClient(void) {
    static id<BTChargeClient> cached;
    static NSObject *token;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ token = [NSObject new]; });
    @synchronized (token) {
        if (!cached) cached = createClient();
        return cached;
    }
}

int bt_native_read(int *limit, int *enabled, int *limits, int capacity, int *count) {
    if (!limit || !enabled || !limits || capacity < 1 || !count) return 5;
    @autoreleasepool { @try {
        id<BTChargeClient> client = makeClient();
        if (!client || ![client isMCLSupported]) return 3;
        NSError *error = nil;
        NSArray *values = [client availableChargeLimitsWithError:&error];
        if (error || ![values isKindOfClass:NSArray.class] || values.count > (NSUInteger)capacity) return 5;
        int n = 0;
        for (id value in values) {
            if (![value isKindOfClass:NSNumber.class]) return 5;
            int v = [value intValue];
            if (v < 20 || v > 100 || [value doubleValue] != v) return 5;
            limits[n++] = v;
        }
        *limit = [client getMCLLimitWithError:&error];
        if (error) return 5;
        unsigned long long state = [client isMCLCurrentlyEnabled:&error];
        if (error || state > 1 || *limit < 20 || *limit > 100 || n == 0) return 5;
        *enabled = (int)state;
        *count = n;
        return 0;
    } @catch (NSException *exception) { return 5; } }
}

int bt_native_set(int limit) {
    if (limit < 20 || limit > 100) return 1;
    @autoreleasepool { @try {
        id<BTChargeClient> client = makeClient();
        if (!client || ![client isMCLSupported]) return 3;
        NSError *error = nil;
        BOOL success = [client setMCLLimit:(unsigned char)limit error:&error];
        return success && !error ? 0 : 5;
    } @catch (NSException *exception) { return 5; } }
}

int bt_native_disable(void) {
    @autoreleasepool { @try {
        id<BTChargeClient> client = makeClient();
        if (!client || ![client isMCLSupported]) return 3;
        NSError *error = nil;
        BOOL success = [client disableMCL:&error];
        return success && !error ? 0 : 5;
    } @catch (NSException *exception) { return 5; } }
}
