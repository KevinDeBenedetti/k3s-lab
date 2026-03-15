# Module: makefiles/80-dev.mk
# ──────────────────────────────────────────────────────────────────────────────
# Developer workflow
# Requires: brew install bats-core prek
# ──────────────────────────────────────────────────────────────────────────────

.PHONY: test test-watch lint lint-install hooks-update

test: ## Run BATS unit tests (offline — no cluster needed)
	@bats tests/bats/

test-watch: ## Re-run BATS tests on every file change (requires: brew install entr)
	@find tests/bats -name '*.bats' -o -name '*.bash' | entr bats tests/bats/

lint: ## Run all linters (shellcheck + kubeconform + yaml) via prek
	@prek run --all-files
	@echo "$(GREEN)✅ All lint checks passed$(RESET)"

lint-install: ## Install prek git hooks (run once after cloning)
	@prek install
	@echo "$(GREEN)✅ prek hooks installed$(RESET)"

hooks-update: ## Update prek hook revisions to latest
	@prek autoupdate
