#ifndef KEYPATH_SESSION_NATIVE_H
#define KEYPATH_SESSION_NATIVE_H

#include <stdbool.h>
#include <stdint.h>

// Narrow bridges for SDK-public notify functions and IOKit message macros.
// No private symbol lookup, power controls, or permission requests.
bool KPSessionRegisterConsoleNotification(bool userChanged, int32_t *token);
bool KPSessionNotificationChanged(int32_t token, bool *changed);
void KPSessionCancelNotification(int32_t token);

uint32_t KPSystemCanSleepMessage(void);
uint32_t KPSystemWillSleepMessage(void);
uint32_t KPSystemWillPowerOnMessage(void);
uint32_t KPSystemHasPoweredOnMessage(void);

#endif
