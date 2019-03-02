## 0.2.0

Added a `--force-https` flag.
Replaced `--output expr` for `--eval <expr>`, because `--output expr` was leaking internals and for it to properly work, the overlay used by nix-prefetch needs to be present as well, so an `--eval` parameter seems a cleaner solution.
Calling `import` as part of an expression would break our use of `scopedImport` (to hijack import call to e.g. `fetchcargo.nix`), this has now been fixed by shadowing the builtin `import` if `scopedImport` needs to be used.
Fixed incorrect nul byte encoding causing it to eat up to three `0` characters.
