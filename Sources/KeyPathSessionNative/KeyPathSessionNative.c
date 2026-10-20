#include "KeyPathSessionNative.h"
#include <stddef.h>
#include <CoreGraphics/CGSession.h>
#include <IOKit/IOMessage.h>
#include <notify.h>

bool KPSessionRegisterConsoleNotification(bool userChanged, int32_t *token) {
    if (token == NULL) return false;
    const char *name = userChanged ? kCGNotifyGUISessionUserChanged : kCGNotifyGUIConsoleSessionChanged;
    return notify_register_check(name, token) == NOTIFY_STATUS_OK;
}

bool KPSessionNotificationChanged(int32_t token, bool *changed) {
    if (changed == NULL) return false;
    int value = 0;
    uint32_t status = notify_check(token, &value);
    *changed = value != 0;
    return status == NOTIFY_STATUS_OK;
}

void KPSessionCancelNotification(int32_t token) {
    (void)notify_cancel(token);
}

uint32_t KPSystemCanSleepMessage(void) { return kIOMessageCanSystemSleep; }
uint32_t KPSystemWillSleepMessage(void) { return kIOMessageSystemWillSleep; }
uint32_t KPSystemWillPowerOnMessage(void) { return kIOMessageSystemWillPowerOn; }
uint32_t KPSystemHasPoweredOnMessage(void) { return kIOMessageSystemHasPoweredOn; }
