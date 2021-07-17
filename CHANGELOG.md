## 0.4.1

- More compatible empty check in regex.
- Remove deprecated `stdenv.lib` and duplicated name.

## 0.4.0

- Experimental flake support.
- Nix 2.4 support, including the new hash style.
- Allow explicitly importing the `nix-prefetch` overlay when the ad-hoc approach fails.
- Added Github Actions to run tests.
- Add more fallbacks for `XDG_RUNTIME_DIR`.
- Prevent retry loops when testing.
- Workaround an incorrect exit code of nix.
- Skip `fetchFromGithub` dummy in `--list`.

## 0.3.1

- Fixed the overlay referencing mecurial rather than subversion for the subversion package.
- Made sure subversion can find the trusted root certificates, so HTTPS does not fail.
- Allowed `nix-prefetch` to be called concurrently by using `mktemp` directories rather than a fixed location.

## 0.3.0

- Fixed potentially being overly aggressive with the scopedImport optimization.
- Fixed issue #1 by allowing arbitrary Nix expressions to be passed with `--input`.
- Fixed issue #2 by no longer inlining the overlay, and thus fixing relative imports.
- Automated updating the examples.
- Added support for `--arg`/`--argstr`/`-I`/`--option` flags.

## 0.2.0

- Added a `--force-https` flag.
- Replaced `--output expr` for `--eval <expr>`, because `--output expr` was leaking internals and for it to properly work, the overlay used by nix-prefetch needs to be present as well, so an `--eval` parameter seems a cleaner solution.
- Calling `import` as part of an expression would break our use of `scopedImport` (to hijack import call to e.g. `fetchcargo.nix`), this has now been fixed by shadowing the builtin `import` if `scopedImport` needs to be used.
- Fixed incorrect nul byte encoding causing it to eat up to three `0` characters.
