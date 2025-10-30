# This is a convenience Makefile wrapping cmake calls
# All targets should be defined in CMake

build := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))build
.PHONY: all
all: build/build.ninja
	ninja -C ${build} symlinks

# empty default to ensure build dir is created when make called with arguments
Makefile: ;
%: build/build.ninja
	ninja -C ${build} $@

build/build.ninja:
	@mkdir -p ${build}
	@cmake -B ${build} -S . -G Ninja
