# Splash Remains Behind Setup Wizard

## Symptom

When initial setup is incomplete, KeyPath briefly shows its branded splash and
then opens the setup wizard. The control-less splash remains visible behind the
wizard, so closing, moving, or losing focus from the wizard makes KeyPath appear
stuck on the splash.

## Cause

The incomplete-setup presentation path called `showSplashWindow()` followed by
`showWizard()`, but never ordered the splash window out after the separate wizard
window became visible. Reopen policy also described its incomplete-setup result
as `showSplash`, making the static window look like the intended destination.

## Fix

Treat the setup wizard as the incomplete-setup surface. After synchronously
presenting the wizard, hide the splash only when the wizard reports visible. If
wizard presentation fails, retain the splash as a fallback so the app does not
disappear without any surface.

The splash remains valid for the brief launch beat and for menu actions that
need it as a sheet host.
