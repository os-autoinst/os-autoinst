# This is a convenience Makefile wrapping cmake calls
# All targets should be defined in CMake

build := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))build
.PHONY: all
all: build/build.ninja ## Build all and create symlinks
	ninja -C ${build} symlinks

.PHONY: help
help: build/build.ninja ## Display this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Internal targets from CMake/Ninja:"
	@ninja -C ${build} help

# empty default to ensure build dir is created when make called with arguments
Makefile: ;
%: build/build.ninja
	ninja -C ${build} $@

build/build.ninja:
	@mkdir -p ${build}
	@cmake -B ${build} -S . -G Ninja
