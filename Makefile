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

ARCHIVE_PATH ?= build/Herezi.xcarchive
BUILD_NUMBER ?= 1

.PHONY: archive upload help generate sync-api lint format verify-static build verify-bundle test check clean

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

verify-bundle: build ## 앱 번들에 동적 프레임워크(NMapsMap)가 임베드됐는지 검사 (없으면 실행 즉시 크래시)
	@test -d "$(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/Herezi.app/Frameworks/NMapsMap.framework" \
		|| { echo "verify-bundle: Herezi.app에 NMapsMap.framework가 없음 — project.yml 앱 타깃에 package: NMapsMap 필요"; exit 1; }
	@echo "verify-bundle: OK"

test: verify-bundle ## 단위 테스트 실행 (시뮬레이터)
	$(XCODEBUILD) test-without-building -quiet

check: lint verify-static test ## PR 전에 반드시 통과해야 하는 전체 검사 (CI와 동일)
	@echo "check: OK"

clean: ## 생성물 삭제
	rm -rf $(PROJECT) $(DERIVED_DATA) Sources/App/Info.plist

archive: generate ## Release 아카이브 (자동 서명, Apple 계정이 Xcode에 로그인돼 있어야 함). BUILD_NUMBER=N
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release -destination 'generic/platform=iOS' \
		-archivePath $(ARCHIVE_PATH) -allowProvisioningUpdates CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) archive -quiet

upload: archive ## 아카이브를 App Store Connect(TestFlight)로 업로드. 앱 레코드가 먼저 있어야 함
	xcodebuild -exportArchive -archivePath $(ARCHIVE_PATH) -exportOptionsPlist ExportOptions.plist \
		-exportPath build/export -allowProvisioningUpdates
