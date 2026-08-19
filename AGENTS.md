# os-autoinst Agent Guidelines

Backend: Perl (Mojolicious), C++ (image processing), QEMU/KVM. Frontend: Perl
test scripts.

## Build & Test Commands

- `make`: Build everything (creates `build/` directory).
- `make symlinks`: Link binaries into source tree (required before running).
- `make check`: Run all tests (CTest).
- `make test-perl-testsuite TESTS="t/your_test.t"`: Run specific Perl tests.

## Conventions

- Code style: Run `make tidy-perl` (or `tools/tidyall --git` for changed files
  only) or `make tidy` to tidy all files (C++, Python, Perl). This MUST be
  done before every commit and before claiming completion.
- Linter: Always run `make test-perl-testsuite TESTS="xt/01-style.t xt/02-perlcritic.t"`
  for Perl changes before claiming completion.
- Testing: Always add tests for new features or bug fixes in `t/`. Prefer
  reusing existing failing test modules (e.g. from `t/data/tests`) for
  integration tests. Prefer self-explanatory test description strings rather
  than in-file comments.
- Dependencies: Update `dependencies.yaml` and run `make update-deps`.

## Constraints

- `tasks/`: Read/write for planning. Never run git operations on this
  directory.
- Never run git clean or any command that deletes unversioned files. Ask for
  confirmation.
