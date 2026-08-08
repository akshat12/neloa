.PHONY: build build-mlx test agent-test qwen-test setup-signing app basic-app unsigned-release run clean

build:
	swift build

build-mlx:
	sh scripts/build-mlx.sh

test:
	swift run Neloa --self-test

agent-test:
	swift run Neloa --agent-smoke-test

qwen-test:
	NELOA_MLX_CONFIGURATION=Debug sh scripts/build-mlx.sh
	NELOA_EXECUTABLE_PATH="$(CURDIR)/.build/arm64-apple-macosx/debug/Neloa" NELOA_APP_OUTPUT_PATH="$(CURDIR)/.build/qwen-qa/Neloa.app" NELOA_FORCE_ADHOC=1 NELOA_EXPECT_MLX_RESOURCES=1 sh scripts/package-app.sh
	.build/qwen-qa/Neloa.app/Contents/MacOS/Neloa --qwen-smoke-test

setup-signing:
	sh scripts/setup-local-signing.sh

app:
	NELOA_MLX_CONFIGURATION=Release sh scripts/build-mlx.sh
	NELOA_EXECUTABLE_PATH="$(CURDIR)/.build/arm64-apple-macosx/release/Neloa" NELOA_EXPECT_MLX_RESOURCES=1 sh scripts/package-app.sh

basic-app:
	sh scripts/package-app.sh

unsigned-release:
	RELEASE_VERSION="$(RELEASE_VERSION)" NELOA_BUILD_NUMBER="$(BUILD_NUMBER)" sh scripts/package-unsigned-release.sh

run: app
	open dist/Neloa.app

clean:
	swift package clean
	rm -rf dist
