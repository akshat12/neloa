.PHONY: build test agent-test setup-signing app unsigned-release run clean

build:
	swift build

test:
	swift run Neloa --self-test

agent-test:
	swift run Neloa --agent-smoke-test

setup-signing:
	sh scripts/setup-local-signing.sh

app:
	sh scripts/package-app.sh

unsigned-release:
	RELEASE_VERSION="$(RELEASE_VERSION)" NELOA_BUILD_NUMBER="$(BUILD_NUMBER)" sh scripts/package-unsigned-release.sh

run: app
	open dist/Neloa.app

clean:
	swift package clean
	rm -rf dist
