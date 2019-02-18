{ prelude, callPackage }:

with prelude;

{
  builtins = customBuiltins;

  # The builtin is also available outside of `builtins`.
  inherit (customBuiltins) fetchTarball;

  hello_rs = callPackage ../contrib/hello_rs { };
}
