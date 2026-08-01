.PHONY: build test agent-test app run clean

build:
	swift build

test:
	swift run Humana --self-test

agent-test:
	swift run Humana --agent-smoke-test

app:
	sh scripts/package-app.sh

run: app
	open dist/Humana.app

clean:
	swift package clean
	rm -rf dist
