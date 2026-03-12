# os-autoinst Agent Guidelines

Backend: Perl (Mojolicious), C++ (image processing), QEMU/KVM. Frontend: Perl
test scripts.

## Build & Test Commands

- `make`: Build everything (creates `build/` directory).
- `make symlinks`: Link binaries into source tree (required before running).
- `make check`: Run all tests (CTest).
- `make test-perl-testsuite TESTS="t/your_test.t"`: Run specific Perl tests.

## Conventions

- Code style: Run `tools/tidyall --all` (or `tools/tidyall --git` for changed
  files only).
- Testing: Always add tests for new features or bug fixes in `t/`.
- Dependencies: Update `dependencies.yaml` and run `make update-deps`.

## Constraints

- `tasks/`: Read/write for planning. Never run git operations on this
  directory.
- Never run git clean or any command that deletes unversioned files. Ask for
  confirmation.
