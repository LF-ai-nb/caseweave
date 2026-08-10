// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "participant/caseweave"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/participant/caseweave"

license = "MIT"

keywords = [ "testing", "pairwise", "covering-array", "constraints", "ci" ]

preferred_target = "wasm"

description = "Deterministic constrained combinatorial test matrix generator for MoonBit."
