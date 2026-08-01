.PHONY: build test app run clean

build:
	swift build

test:
	swift run Humana --self-test

app:
	sh scripts/package-app.sh

run: app
	open dist/Humana.app

clean:
	swift package clean
	rm -rf dist
