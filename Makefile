## KeyPath Makefile

.PHONY: test core-tests coverage coverage-full coverage-reuse

dev:
	SKIP_KANATA_BUILD=1 LAUNCH_APP=1 ./Scripts/build-dev-local.sh

test:
	./run-core-tests.sh

core-tests:
	CI_INTEGRATION_TESTS=true ./run-core-tests.sh

coverage:
	./Scripts/generate-coverage.sh

coverage-full:
	./Scripts/generate-coverage.sh --full

coverage-reuse:
	./Scripts/generate-coverage.sh --reuse
