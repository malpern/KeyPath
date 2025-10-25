## KeyPath Makefile

.PHONY: test core-tests coverage coverage-full coverage-reuse

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

