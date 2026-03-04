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
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running ShellCheck..."; \
		shellcheck --shell=bash --severity=warning bin/muster bin/muster-mcp lib/core/*.sh lib/commands/*.sh lib/tui/*.sh lib/skills/*.sh || exit 1; \
		find templates/hooks -name '*.sh' -print0 | xargs -0 shellcheck --shell=bash --severity=warning --exclude=SC1083,SC2034 || exit 1; \
		echo "ShellCheck passed"; \
	else \
		echo "shellcheck not installed, skipping (brew install shellcheck)"; \
	fi
