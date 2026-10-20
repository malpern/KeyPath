# Permission prompts before user action

Opening diagnostic/emergency event taps or HID managers without existing Input Monitoring can prompt implicitly. Passive status checks alone do not prevent this. Gate the API entry points themselves with non-requesting access preflights, including keyboard detection and global hotkeys. Wizard button actions remain the only explicit requests. Verify denied-permission first launch on a clean machine; an already-granted host cannot prove absence of prompts.
