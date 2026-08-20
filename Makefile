.PHONY: build build-mlx test trigger-test agent-test qwen-test qwen-8bit-test model-eval model-eval-8bit model-eval-compare product-video product-video-frames setup-signing app basic-app unsigned-release run clean

build:
	swift build

build-mlx:
	sh scripts/build-mlx.sh

test:
	swift run Neloa --self-test

trigger-test:
	swift run Neloa --file-trigger-smoke-test

agent-test:
	swift run Neloa --agent-smoke-test

qwen-test:
	NELOA_MLX_CONFIGURATION=Debug sh scripts/build-mlx.sh
	NELOA_EXECUTABLE_PATH="$(CURDIR)/.build/arm64-apple-macosx/debug/Neloa" NELOA_APP_OUTPUT_PATH="$(CURDIR)/.build/qwen-qa/Neloa.app" NELOA_FORCE_ADHOC=1 NELOA_EXPECT_MLX_RESOURCES=1 sh scripts/package-app.sh
	.build/qwen-qa/Neloa.app/Contents/MacOS/Neloa --qwen-smoke-test

qwen-8bit-test:
	NELOA_MLX_CONFIGURATION=Debug sh scripts/build-mlx.sh
	NELOA_EXECUTABLE_PATH="$(CURDIR)/.build/arm64-apple-macosx/debug/Neloa" NELOA_APP_OUTPUT_PATH="$(CURDIR)/.build/qwen-qa/Neloa.app" NELOA_FORCE_ADHOC=1 NELOA_EXPECT_MLX_RESOURCES=1 sh scripts/package-app.sh
	.build/qwen-qa/Neloa.app/Contents/MacOS/Neloa --qwen-8bit-smoke-test

model-eval:
	NELOA_MLX_CONFIGURATION=Debug sh scripts/build-mlx.sh
	NELOA_EXECUTABLE_PATH="$(CURDIR)/.build/arm64-apple-macosx/debug/Neloa" NELOA_APP_OUTPUT_PATH="$(CURDIR)/.build/model-eval/Neloa.app" NELOA_FORCE_ADHOC=1 NELOA_EXPECT_MLX_RESOURCES=1 sh scripts/package-app.sh
	mkdir -p .build/model-eval/reports
	NELOA_EVAL_COMMIT="$$(git rev-parse HEAD 2>/dev/null || true)" NELOA_MODEL_EVAL_REPORT="$(CURDIR)/.build/model-eval/reports/qwen3-vl-4b-4bit.json" .build/model-eval/Neloa.app/Contents/MacOS/Neloa --model-eval

model-eval-8bit:
	NELOA_MLX_CONFIGURATION=Debug sh scripts/build-mlx.sh
	NELOA_EXECUTABLE_PATH="$(CURDIR)/.build/arm64-apple-macosx/debug/Neloa" NELOA_APP_OUTPUT_PATH="$(CURDIR)/.build/model-eval/Neloa.app" NELOA_FORCE_ADHOC=1 NELOA_EXPECT_MLX_RESOURCES=1 sh scripts/package-app.sh
	mkdir -p .build/model-eval/reports
	NELOA_EVAL_COMMIT="$$(git rev-parse HEAD 2>/dev/null || true)" NELOA_MODEL_EVAL_REPORT="$(CURDIR)/.build/model-eval/reports/qwen3-vl-4b-8bit.json" .build/model-eval/Neloa.app/Contents/MacOS/Neloa --model-eval-8bit

model-eval-compare:
	@test -n "$(BASELINE)" || (echo "BASELINE=/path/to/baseline.json is required" >&2; exit 1)
	@test -n "$(CANDIDATE)" || (echo "CANDIDATE=/path/to/candidate.json is required" >&2; exit 1)
	NELOA_MODEL_EVAL_BASELINE="$(abspath $(BASELINE))" NELOA_MODEL_EVAL_CANDIDATE="$(abspath $(CANDIDATE))" NELOA_MODEL_EVAL_COMPARISON_REPORT="$(CURDIR)/.build/model-eval/reports/comparison.json" swift run Neloa --compare-model-evals

product-video:
	swift scripts/render-product-video.swift

product-video-frames:
	swift scripts/extract-product-video-frames.swift

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
