#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <Carbon/Carbon.h>
#include <unistd.h>
#include <dlfcn.h>

// Disposable-lab probe. Records counters, never text or arbitrary keycodes.
static FILE *out;
static unsigned hidCount, tapCount, remapCount;
static bool remap;
static void *runtime;
static bool (*sendInput)(void *, unsigned long long, unsigned int, unsigned int, char *, size_t);
static int (*recvOutput)(void *, unsigned long long *, unsigned int *, unsigned int *, char *, size_t);
static unsigned engineInput, engineOutput, tagged;
static const int64_t marker = 0x4b505052;
static bool held[3], hrm;
static unsigned ctrlChord;
@interface ProbeTarget : NSTextView
@end
@implementation ProbeTarget
- (void)keyDown:(NSEvent *)e {
  if (e.keyCode == 0 && (e.modifierFlags & NSEventModifierFlagControl)) ++ctrlChord;
  [super keyDown:e];
}
@end
static void stopApp(CFRunLoopTimerRef timer, void *ctx) {
  [NSApp stop:nil];
  [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
}
static void drain(CFRunLoopTimerRef timer, void *ctx) {
  if (!runtime) return;
  unsigned long long v; unsigned p, c; char err[512] = {0}; int status;
  while ((status = recvOutput(runtime, &v, &p, &c, err, sizeof err)) == 1) {
    // Deliberately bounded adapter: q, a and left Control only.
    int slot = c == 4 ? 0 : c == 20 ? 1 : c == 224 ? 2 : -1;
    if (p != 7 || slot < 0 || v > 1) { fprintf(out, "OUTPUT unsupported\n"); continue; }
    held[slot] = v == 1;
    CGEventRef e = CGEventCreateKeyboardEvent(NULL, slot == 0 ? 0 : slot == 1 ? 12 : 59, v == 1);
    if (slot == 2) CGEventSetType(e, kCGEventFlagsChanged);
    CGEventSetFlags(e, held[2] ? kCGEventFlagMaskControl : 0);
    CGEventSetIntegerValueField(e, kCGEventSourceUserData, marker);
    CGEventPost(kCGSessionEventTap, e); CFRelease(e); ++engineOutput;
  }
  if (status < 0) fprintf(out, "OUTPUT error=%s\n", err);
}
static void value(void *ctx, IOReturn result, void *sender, IOHIDValueRef v) {
  if (result == kIOReturnSuccess) ++hidCount;
}
static CGEventRef event(CGEventTapProxy proxy, CGEventType type, CGEventRef e, void *ctx) {
  if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) return e;
  ++tapCount;
  if (CGEventGetIntegerValueField(e, kCGEventSourceUserData) == marker) { ++tagged; return e; }
  if (runtime && (type == kCGEventKeyDown || type == kCGEventKeyUp) &&
      (CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode) == 12 ||
       (hrm && CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode) == 0))) {
    char err[512] = {0};
    unsigned usage = CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode) == 12 ? 20 : 4;
    if (sendInput(runtime, type == kCGEventKeyDown ? 1 : 0, 7, usage, err, sizeof err)) {
      ++engineInput; return NULL;
    }
    fprintf(out, "INPUT failed=%s\n", err); return e;
  }
  if (remap && (type == kCGEventKeyDown || type == kCGEventKeyUp) &&
      CGEventGetIntegerValueField(e, kCGKeyboardEventKeycode) == 12) {
    CGEventSetIntegerValueField(e, kCGKeyboardEventKeycode, 0); ++remapCount;
  }
  return e;
}
int main(int argc, const char **argv) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"permission-probe.log"];
    out = fopen(path.UTF8String, "a"); setbuf(out, NULL);
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    fprintf(out, "IDENTITY bundle=%s version=%s path=%s ppid=%d\n", NSBundle.mainBundle.bundleIdentifier.UTF8String, version.UTF8String, NSBundle.mainBundle.bundlePath.UTF8String, getppid());
    fprintf(out, "START pid=%d uid=%d ax=%d listen=%d secure=%d\n", getpid(), getuid(), AXIsProcessTrusted(), IOHIDCheckAccess(kIOHIDRequestTypeListenEvent), IsSecureEventInputEnabled());
    if ([args containsObject:@"--request-ax"]) {
      NSDictionary *o = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES};
      AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)o);
    }
    if ([args containsObject:@"--request-im"]) IOHIDRequestAccess(kIOHIDRequestTypeListenEvent);
    if ([args containsObject:@"--check-only"]) return 0;
    bool secureTarget = [args containsObject:@"--secure-target"];
    if (secureTarget) { EnableSecureEventInput(); fprintf(out, "SECURE pid=%d enabled=%d\n", getpid(), IsSecureEventInputEnabled()); }
    remap = [args containsObject:@"--remap"];
    hrm = [args containsObject:@"--hrm"];
    if ([args containsObject:@"--engine"] || hrm) {
      NSString *lib = [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib"];
      if (![[NSFileManager defaultManager] fileExistsAtPath:lib]) lib = @"/Applications/KeyPath.app/Contents/Library/KeyPath/libkeypath_kanata_host_bridge.dylib";
      void *handle = dlopen(lib.UTF8String, RTLD_NOW | RTLD_LOCAL);
      if (!handle) { fprintf(out, "ENGINE dlopen=%s\n", dlerror()); return 2; }
      void *(*create)(const char *, unsigned short, char *, size_t) = dlsym(handle, "keypath_kanata_bridge_create_passthru_runtime");
      bool (*start)(void *, char *, size_t) = dlsym(handle, "keypath_kanata_bridge_start_passthru_runtime");
      sendInput = dlsym(handle, "keypath_kanata_bridge_passthru_send_input");
      recvOutput = dlsym(handle, "keypath_kanata_bridge_passthru_try_recv_output");
      if (!create || !start || !sendInput || !recvOutput) { fprintf(out, "ENGINE missing-ABI\n"); return 2; }
      NSString *cfg = [NSHomeDirectory() stringByAppendingPathComponent:@"permission-probe.kbd"];
      NSString *config = hrm ? @"(defcfg process-unmapped-keys yes)\n(defsrc q a)\n(deflayer base (tap-hold 200 200 q lctl) a)\n" : @"(defcfg process-unmapped-keys yes)\n(defsrc q)\n(deflayer base a)\n";
      [config writeToFile:cfg atomically:YES encoding:NSUTF8StringEncoding error:nil];
      char err[512] = {0}; runtime = create(cfg.UTF8String, 0, err, sizeof err);
      fprintf(out, "ENGINE created=%d error=%s\n", runtime != NULL, err);
      if (!runtime || !start(runtime, err, sizeof err)) { fprintf(out, "ENGINE start-failed=%s\n", err); return 2; }
      CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent(), .005, 0, 0, drain, NULL);
      CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
      fprintf(out, "ENGINE started=1\n");
    }
    NSTextView *target = nil; NSWindow *window = nil;
    if ([args containsObject:@"--target"]) {
      window = [[NSWindow alloc] initWithContentRect:NSMakeRect(200,200,400,200) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
      window.title = @"Permission Probe Test Target";
      target = [[ProbeTarget alloc] initWithFrame:NSMakeRect(0,0,400,200)];
      [window setContentView:target]; [window makeKeyAndOrderFront:nil];
      [NSApp activateIgnoringOtherApps:YES]; [window makeFirstResponder:target];
    }
    IOHIDManagerRef mgr = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    NSDictionary *match = @{@kIOHIDDeviceUsagePageKey:@1, @kIOHIDDeviceUsageKey:@6};
    IOHIDManagerSetDeviceMatching(mgr, (__bridge CFDictionaryRef)match);
    IOHIDManagerRegisterInputValueCallback(mgr, value, NULL);
    IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
    IOReturn status = IOHIDManagerOpen(mgr, [args containsObject:@"--seize"] ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone);
    CFSetRef devices = IOHIDManagerCopyDevices(mgr);
    fprintf(out, "HID open=0x%x devices=%ld\n", status, devices ? CFSetGetCount(devices) : 0L);
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) | CGEventMaskBit(kCGEventFlagsChanged) | CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp) | CGEventMaskBit(kCGEventScrollWheel);
    CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, (remap || runtime) ? kCGEventTapOptionDefault : kCGEventTapOptionListenOnly, mask, event, NULL);
    fprintf(out, "TAP created=%d remap=%d\n", tap != NULL, remap);
    if (tap) {
      CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(NULL, tap, 0);
      CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
      CGEventTapEnable(tap, true);
    }
    // Bounded lifetime and clean-exit releases limit the experiment.
    // This is not a production timeout/crash watchdog; no persistent remapper is installed.
    if (target) {
      CFRunLoopTimerRef stop = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent()+20, 0, 0, 0, stopApp, NULL);
      CFRunLoopAddTimer(CFRunLoopGetCurrent(), stop, kCFRunLoopCommonModes);
      [NSApp run];
    } else CFRunLoopRunInMode(kCFRunLoopDefaultMode, 20, false);
    for (int slot = 0; slot < 3; ++slot) if (held[slot]) {
      CGEventRef release = CGEventCreateKeyboardEvent(NULL, slot == 0 ? 0 : slot == 1 ? 12 : 59, false);
      if (slot == 2) CGEventSetType(release, kCGEventFlagsChanged);
      CGEventSetFlags(release, 0);
      CGEventSetIntegerValueField(release, kCGEventSourceUserData, marker);
      CGEventPost(kCGSessionEventTap, release); CFRelease(release);
      fprintf(out, "RECOVERY released-output-slot=%d\n", slot);
    }
    fprintf(out, "END pid=%d ax=%d listen=%d secure=%d hid=%u tap=%u remaps=%u engine-in=%u engine-out=%u tagged=%u\n", getpid(), AXIsProcessTrusted(), IOHIDCheckAccess(kIOHIDRequestTypeListenEvent), IsSecureEventInputEnabled(), hidCount, tapCount, remapCount, engineInput, engineOutput, tagged);
    if (target) fprintf(out, "TARGET pid=%d expected-a=%d has-q=%d length=%lu engine-in=%u engine-out=%u tagged=%u ctrl-chord=%u\n", getpid(), [target.string isEqualToString:@"a"], [target.string containsString:@"q"], (unsigned long)target.string.length, engineInput, engineOutput, tagged, ctrlChord);
    if (secureTarget) DisableSecureEventInput();
    IOHIDManagerClose(mgr, kIOHIDOptionsTypeNone);
  }
}
