#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDDeviceKeys.h>
#include <IOKit/hidsystem/IOHIDUserDevice.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static const uint8_t keyboard_descriptor[] = {
    0x05, 0x01,       // Usage Page (Generic Desktop)
    0x09, 0x06,       // Usage (Keyboard)
    0xa1, 0x01,       // Collection (Application)
    0x05, 0x07,       // Usage Page (Keyboard)
    0x19, 0xe0,       // Usage Minimum (Left Control)
    0x29, 0xe7,       // Usage Maximum (Right GUI)
    0x15, 0x00,       // Logical Minimum (0)
    0x25, 0x01,       // Logical Maximum (1)
    0x75, 0x01,       // Report Size (1)
    0x95, 0x08,       // Report Count (8)
    0x81, 0x02,       // Input (Data, Variable, Absolute)
    0x95, 0x01,       // Report Count (1)
    0x75, 0x08,       // Report Size (8)
    0x81, 0x01,       // Input (Constant)
    0x95, 0x06,       // Report Count (6)
    0x75, 0x08,       // Report Size (8)
    0x15, 0x00,       // Logical Minimum (0)
    0x25, 0x65,       // Logical Maximum (101)
    0x05, 0x07,       // Usage Page (Keyboard)
    0x19, 0x00,       // Usage Minimum (Reserved)
    0x29, 0x65,       // Usage Maximum (Keyboard Application)
    0x81, 0x00,       // Input (Data, Array, Absolute)
    0xc0,             // End Collection
};

static void set_number(CFMutableDictionaryRef properties, CFStringRef key, int value) {
    CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &value);
    CFDictionarySetValue(properties, key, number);
    CFRelease(number);
}

int main(int argc, char **argv) {
    if (argc != 2 || strcmp(argv[1], "q") != 0) {
        fprintf(stderr, "usage: keypath-hid-input q\n");
        return 2;
    }

    CFMutableDictionaryRef properties = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    CFDataRef descriptor = CFDataCreate(
        kCFAllocatorDefault, keyboard_descriptor, sizeof(keyboard_descriptor));
    CFDictionarySetValue(properties, CFSTR(kIOHIDReportDescriptorKey), descriptor);
    CFDictionarySetValue(properties, CFSTR(kIOHIDProductKey), CFSTR("KeyPath Lab Input"));
    CFDictionarySetValue(properties, CFSTR(kIOHIDSerialNumberKey), CFSTR("lease-scoped"));
    set_number(properties, CFSTR(kIOHIDVendorIDKey), 0x4b50);
    set_number(properties, CFSTR(kIOHIDProductIDKey), 0x0001);
    set_number(properties, CFSTR(kIOHIDPrimaryUsagePageKey), 0x01);
    set_number(properties, CFSTR(kIOHIDPrimaryUsageKey), 0x06);

    IOHIDUserDeviceRef device =
        IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault, properties, 0);
    CFRelease(descriptor);
    CFRelease(properties);
    if (device == NULL) {
        fprintf(stderr, "keypath-hid-input: virtual keyboard creation failed\n");
        return 1;
    }

    usleep(750000);
    uint8_t press[8] = {0, 0, 0x14, 0, 0, 0, 0, 0};
    uint8_t release[8] = {0};
    IOReturn press_result = IOHIDUserDeviceHandleReportWithTimeStamp(
        device, mach_absolute_time(), press, sizeof(press));
    usleep(50000);
    IOReturn release_result = IOHIDUserDeviceHandleReportWithTimeStamp(
        device, mach_absolute_time(), release, sizeof(release));
    usleep(250000);
    CFRelease(device);

    if (press_result != kIOReturnSuccess || release_result != kIOReturnSuccess) {
        fprintf(stderr, "keypath-hid-input: report dispatch failed: 0x%x 0x%x\n",
                press_result, release_result);
        return 1;
    }
    printf("hid_input\tq\n");
    return 0;
}
