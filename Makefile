.PHONY: build build-mlx test agent-test setup-signing app basic-app unsigned-release run clean

build:
	swift build

build-mlx:
	sh scripts/check-mlx-toolchain.sh
	NELOA_ENABLE_MLX=1 swift build

test:
	swift run Neloa --self-test

agent-test:
	swift run Neloa --agent-smoke-test

setup-signing:
	sh scripts/setup-local-signing.sh

app:
	sh scripts/check-mlx-toolchain.sh
	NELOA_ENABLE_MLX=1 sh scripts/package-app.sh

basic-app:
	sh scripts/package-app.sh

unsigned-release:
	RELEASE_VERSION="$(RELEASE_VERSION)" NELOA_BUILD_NUMBER="$(BUILD_NUMBER)" sh scripts/package-unsigned-release.sh

run: app
	open dist/Neloa.app

clean:
	swift package clean
	rm -rf dist
