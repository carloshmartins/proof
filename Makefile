PREFIX ?= $(HOME)/.local
PROOF_HOME ?= $(HOME)/.proof
SKILL_DIR ?= $(HOME)/.agents/skills/proof

.PHONY: build test install uninstall runner

build:
	swift build -c release

test:
	swift test

# Installs the binary, the runner sources (built on first `proof ui` use) and the agent skill.
# Point SKILL_DIR at the skills folder your agent reads, e.g. make install SKILL_DIR=~/.myagent/skills/proof
install: build
	install -d "$(PREFIX)/bin"
	install -m 755 "$$(swift build -c release --show-bin-path)/proof" "$(PREFIX)/bin/proof"
	PROOF_HOME="$(PROOF_HOME)" "$$(swift build -c release --show-bin-path)/proof" setup --skill-dir "$(SKILL_DIR)"
	@echo "installed: $(PREFIX)/bin/proof"
	@echo "next: cd <your repo> && proof init --scheme <Scheme> --simulator \"iPhone 16\" && proof doctor"

# Prebuild the runner now instead of on first use.
runner: install
	"$(PREFIX)/bin/proof" ui start --rebuild && "$(PREFIX)/bin/proof" ui stop

uninstall:
	rm -f "$(PREFIX)/bin/proof"
	rm -rf "$(PROOF_HOME)/runner" "$(SKILL_DIR)"
	@echo "kept $(PROOF_HOME)/config.json and sessions; delete $(PROOF_HOME) to remove everything"
