GH_TOKEN ?= $(shell which gh >/dev/null && gh auth token || echo "gh-tool-not-installed-see-readme")

GOCMD := GOPRIVATE="github.com/yalochat" go

DCCMD := \
	GH_TOKEN=$(GH_TOKEN) \
	SCHEMAS_TAG=$(SCHEMAS_TAG) \
	docker compose $(shell find ./docker -maxdepth 1 -name "docker-compose*" -not \( -path .git -prune \) | sed -e 's/^/-f /')


# Check if running in GitHub Actions
ifdef GITHUB_ACTIONS
    DC_UP_FLAGS := -d --quiet-pull
else
    DC_UP_FLAGS := -d
endif

generate:
	$(GOCMD) generate ./...
.PHONY: generate

test-functional:
	$(GOCMD) test -v -tags=functional -coverprofile=coverage.out ./test/functional/...
.PHONY: test-functional

test:
	$(GOCMD) test -v -tags=unit -coverprofile=coverage.out ./pkg/... ./internal/...
.PHONY: test

test/%:
	$(GOCMD) test -v -count=1 ./$*/...

coverage: test
	$(GOCMD) tool cover -func=coverage.out
.PHONY: coverage

htmlcoverage: test
	$(GOCMD) tool cover -html=coverage.out
.PHONY: htmlcoverage

gitconfig:
	git config --global url."git@github.com:yalochat".insteadOf "https://github.com/yalochat"
.PHONY: gitconfig

lint:
	$(GOCMD) vet ./...
.PHONY: lint

download:
	$(GOCMD) mod download
.PHONY: download

tidy:
	$(GOCMD) mod tidy
.PHONY: tidy

changelog:
	git-chglog --path "services/taskmanager/**/*" --next-tag=$(shell cat VERSION | xargs) -o CHANGELOG.md
.PHONY: changelog

run-api:
	$(GOCMD) run cmd/api/main.go
.PHONY: run-api

run-grpc:
	$(GOCMD) run cmd/grpc/main.go
.PHONY: run-grpc

dist/%:
	$(GOCMD) build -o dist/$* ./cmd/$*

up/%:
	@$(DCCMD) up $(DC_UP_FLAGS) $*

build/%:
	@$(DCCMD) build $*

down/%:
	@docker stop $(shell docker inspect -f '{{.Name}}' $(shell $(DCCMD) ps -q $*) | cut -c2-)

down-clean:
	@$(DCCMD) down --volumes --remove-orphans
.PHONY: down-clean

down:
	@$(DCCMD) down
.PHONY: down

binaries: dist/api dist/grpc
.PHONY: binaries

build: build/api
.PHONY: build

up: up/api
.PHONY: up

tools:
	@echo "installing tools"
	$(GOCMD) install github.com/gotesttools/gotestfmt/v2/cmd/gotestfmt@latest
	$(GOCMD) install google.golang.org/protobuf/cmd/protoc-gen-go
	$(GOCMD) install google.golang.org/grpc/cmd/protoc-gen-go-grpc
	$(GOCMD) install github.com/swaggo/swag/cmd/swag@latest
	asdf reshim golang
	@echo "install complete"

clean:
	rm -f dist/*
	rm -f coverage.out
	rm -f openapi.yaml
	rm -rf bindings
	rm -f openapitools.json
.PHONY: clean

generateOpenApiSpec:
	@mainPath=$$(grep -lR '//\s*@title' | head -n 1); \
	mainFileDir=$$(dirname $$mainPath); \
	annotationPrefix="//\s*@"; \
	dirs=$$(grep -lR --exclude-dir=.git "$$annotationPrefix" | xargs dirname | uniq | tr '\n' ',' | sed 's/,$$/\n/'); \
	swag init --parseDependency --parseInternal --output . --outputTypes yaml --dir "$$mainFileDir,$$dirs"; \
	mv swagger.yaml openapi.yaml

SPEC_FILE := openapi.yaml
SERVICE_DIR := .
NAME_MAPPINGS := "_id=UnderscoreId"
go-binding: generateOpenApiSpec
	@echo "Checking if openapi-generator-cli is installed..."
	@if ! command -v openapi-generator-cli &> /dev/null; then \
		echo "Installing"; \
		npm install @openapitools/openapi-generator-cli -g; \
	else \
    		echo "Installed"; \
    	fi


	@echo "Removing existing Go binding"
	GO_BINDING_FOLDER=${SERVICE_DIR}/bindings/go
	if [ -d $$GO_BINDING_FOLDER ]; then \
		rm -rf $$GO_BINDING_FOLDER; \
	else \
		echo "$$GO_BINDING_FOLDER does not exist, is omitted."; \
	fi

	@echo "Generating Go binding"
	npx @openapitools/openapi-generator-cli generate \
		--openapi-normalizer KEEP_ONLY_FIRST_TAG_IN_OPERATION=true \
		--name-mappings ${NAME_MAPPINGS} \
		-i ${SPEC_FILE} \
		-g go \
		-o bindings/go

	@echo "Formatting Go binding and running tests"
	cd ${SERVICE_DIR}/bindings/go && \
	go mod tidy && \
	go test ./...

	@echo "Removing unnecessary files"
	cd ./bindings/go && \
	rm -r .openapi-generator api docs test .openapi-generator-ignore .travis.yml git_push.sh README.md

	echo "Replacing module path in go.mod"
	sed -i '' 's|GIT_USER_ID/GIT_REPO_ID|yalochat/customer-profiles-api/services/audiences/bindings/go|g' bindings/go/go.mod

	@echo "Go binding generated successfully"

replace-core:
	@$(GOCMD) mod edit -replace github.com/yalochat/customer-profiles-api=../..
.PHONY: replace-core

MODULE=github.com/yalochat/customer-profiles-api/services/audiences
PROTO_SRC_DIR=.
PROTO_GEN_DIR=.

# Protoc commands
PROTOC=$(shell asdf which protoc)
PROTOC_GEN_GO=protoc-gen-go
PROTOC_GEN_GO_GRPC=protoc-gen-go-grpc
proto:
	@echo "Generating Go code from proto files..."
	$(PROTOC) \
		--proto_path=$(PROTO_SRC_DIR) \
		--go_out=. \
		--go_opt=paths=import,module=$(MODULE) \
		--go-grpc_out=$(PROTO_GEN_DIR) \
		--go-grpc_opt=paths=import,module=$(MODULE) \
		`find $(PROTO_SRC_DIR) -name '*.proto' -print | sort`
	@echo "Protobuf generation complete."
.PHONY: proto
