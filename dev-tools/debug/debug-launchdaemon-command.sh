#!/bin/bash

# Deprecated: the InstallerEngine façade now owns all LaunchDaemon install/repair flows.
# Use the Swift debug helpers that call InstallerEngine directly:
#   swift dev-tools/debug/debug-service-install.swift
#   swift dev-tools/debug/debug-unhealthy-services-fix.swift
echo "⚠️  This script is deprecated. Use the InstallerEngine debug helpers instead."
exit 1
