.PHONY: test lint

test:
	@bash tests/test_runner.sh

lint:
	@echo "Checking syntax..."
	@bash -n bin/muster
	@bash -n bin/muster-mcp
	@for f in lib/core/*.sh lib/commands/*.sh lib/tui/*.sh lib/skills/*.sh; do \
		bash -n "$$f" || exit 1; \
	done
	@echo "All files pass syntax check"
