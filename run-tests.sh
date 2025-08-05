#!/bin/bash
set -e

echo "Running Swift unit tests..."
swift test

echo "Running integration tests..."
./test-kanata-system.sh
./test-hot-reload.sh
./test-service-status.sh
./test-installer.sh

echo "All tests completed successfully!"