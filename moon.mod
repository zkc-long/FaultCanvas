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

name = "zkc-long/faultcanvas"

version = "0.1.0"

readme = "README.mbt.md"

repository = "https://github.com/zkc-long/faultcanvas"

license = "Apache-2.0"

keywords = [
  "http",
  "proxy",
  "fault-injection",
  "service-virtualization",
  "testing",
]

preferred_target = "native"

description = "Programmable HTTP fault proxy and stateful service virtualization gateway for MoonBit"

import {
  "moonbitlang/async@0.21.3",
}
