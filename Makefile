# This is a convenience Makefile wrapping cmake calls
# All targets should be defined in CMake

.PHONY: all
all: build/CMakeCache.txt
	ninja -C build/ all

.DEFAULT: build/CMakeCache.txt
	ninja -C build/ $@

build/CMakeCache.txt:
	@mkdir -p build
	@(cd build && cmake -GNinja ..)

# Devel::Cover works best with a simple "test" target in a top-level Makefile
# Call "check" for all tests and checks
.PHONY: test
test: all
	prove -I. -r t/
