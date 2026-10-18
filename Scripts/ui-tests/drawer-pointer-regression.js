// Run in cua_repl after obtaining the current KeyPath overlay screenshot.
// Set drawerPoint from the top-right keyboard key's center in that screenshot.
// Do not use AXPress/index activation: it bypasses the faulty pointer recognizers.
// Preconditions: onboarding complete; inspector initially open; no user interaction
// during the two clicks. Refresh the screenshot if the window moves or resizes.
var drawerApp = await cua.getApp('/Applications/KeyPath.app');
var drawerPoint = [1230, 80]; // Air screenshot fixture, 2026-10-11
await drawerApp.click(drawerPoint);
var closed = await drawerApp.getAXState({disableDiffing: true});
if (closed.includes('inspector-tab-mapper')) {
    throw new Error('REGRESSION: clicking the top-right drawer key did not close the inspector');
}
await drawerApp.click(drawerPoint);
var opened = await drawerApp.getAXState({disableDiffing: true});
if (!opened.includes('inspector-tab-mapper')) {
    throw new Error('REGRESSION: clicking the top-right drawer key did not open the inspector');
}
