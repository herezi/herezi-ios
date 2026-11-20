# herezi-ios 명령 모음. 자세한 설명은 AGENTS.md 참고.
SHELL := /bin/bash

PROJECT      := Herezi.xcodeproj
SCHEME       := Herezi
DERIVED_DATA ?= build/DerivedData
SIMULATOR_ID ?= $(shell scripts/pick-simulator.sh)
DESTINATION  ?= platform=iOS Simulator,id=$(SIMULATOR_ID)
SWIFT_FORMAT := $(shell xcrun --find swift-format 2>/dev/null)
XCODEBUILD   := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) \
                -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO

.PHONY: help generate sync-api lint format verify-static build test check clean

help: ## 명령 목록
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-14s %s\n", $$1, $$2}'

generate: ## project.yml -> Herezi.xcodeproj 생성 (XcodeGen)
	xcodegen generate --quiet

sync-api: ## herezi-api의 api/openapi.yaml 복사
	scripts/sync-api.sh

lint: ## swift-format lint (Xcode 툴체인에 없으면 건너뜀)
ifeq ($(SWIFT_FORMAT),)
	@echo "lint: xcrun swift-format 없음 — 건너뜀"
else
	xcrun swift-format lint --strict --recursive --parallel Sources Tests
endif

format: ## swift-format으로 코드 정리
ifeq ($(SWIFT_FORMAT),)
	@echo "format: xcrun swift-format 없음 — 건너뜀"
else
	xcrun swift-format format --in-place --recursive --parallel Sources Tests
endif

verify-static: ## 모듈 경계 + API 계약 드리프트 검사
	scripts/check-architecture.sh
	scripts/check-api-drift.sh

build: generate ## 앱 + 테스트 빌드 (시뮬레이터)
	$(XCODEBUILD) build-for-testing -quiet

test: build ## 단위 테스트 실행 (시뮬레이터)
	$(XCODEBUILD) test-without-building -quiet

check: lint verify-static test ## PR 전에 반드시 통과해야 하는 전체 검사 (CI와 동일)
	@echo "check: OK"

clean: ## 생성물 삭제
	rm -rf $(PROJECT) $(DERIVED_DATA) Sources/App/Info.plist
