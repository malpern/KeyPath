# Uninstall completed but application remained open

The backup existed and the application had been moved out of Applications, but terminate was called while the uninstall sheet remained modal. Logs never entered applicationShouldTerminate and the old process kept reconnecting to its stopped runtime. Dismiss the sheet before requesting termination, allowing the dismissal to reach the main run loop. Do not reinstall the application to recover an uninstall.

Second failure: after sheet dismissal, applicationShouldTerminate entered but repeated stop awaited configuration admission that successful uninstall intentionally suspends. Record successful uninstall cleanup in RuntimeCoordinator and let the termination callback reuse that result. Failed uninstall and ordinary Quit still run normal admitted cleanup.
