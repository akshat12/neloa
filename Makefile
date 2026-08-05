.PHONY: build test agent-test setup-signing app run clean

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

run: app
	open dist/Neloa.app

clean:
	swift package clean
	rm -rf dist
