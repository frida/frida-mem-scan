# frida-mem-scan

Fast SIMD-accelerated memory scanner for Frida. Targets either the
current process or any other process by PID, with the same API.

The scanner core is a self-contained, relocation-free assembly blob
(SSE4.1 on x86_64, NEON on arm64) that's copied into a JIT page at
load time. On modern hardware it saturates memory bandwidth on the
parallel path; see `src/README.md` for measurements on a specific
machine. The cross-process path uses the platform's native VM API
(mach\_vm\_\* on macOS, with Windows and Linux backends stubbed for
future contributions).

## Install

```sh
frida-pm install frida-mem-scan
```

## Usage

```ts
import { Target } from "frida-mem-scan";

// In-process scan: find every Hv::Vm vtable pointer.
const me = Target.self();
const hits = me.find(["Hypervisor!_ZTVN2Hv2VmE+16"]);
for (const h of hits) {
    console.log(h.addr);
}

// Cross-process scan, restricted to readable regions <= 100 MB:
const t = Target.pid(9549);
const hits = t.find(["Hypervisor!_ZTVN2Hv2VmE+16"], {
    filter: { readable: true, maxBytes: 100 * 1024 * 1024 },
});

// Raw memory read (works for both self and cross-process):
const bytes = t.read(ptr("0x104dbd560"), 128);
```

Targets are either raw addresses (`NativePointer`, `UInt64`, or
`number`) or `<module>!<symbol>[+<offset>]` strings that resolve
against the loaded image set. The `+16` convention matches the
Itanium C++ ABI vtable address-point so you can scan for object
instances by their class name.

By default a mask of `0x00007ffffffffff8` is applied to each candidate
slot before equality comparison; that strips arm64e PAC and the
non-pointer-isa flag bits in one go. Pass your own `mask` to opt out
or scan for something else (e.g. `~0` for raw equality).

## API

```ts
class Target {
    static self(): Target
    static pid(pid: number): Target

    find(targets: TargetSpec[], opts?: FindOpts): ScanHit[]
    read(addr: NativePointer, size: number): ArrayBuffer
    regions(filter?: RegionFilter): Iterable<Region>
}

interface FindOpts {
    mask?: UInt64
    filter?: RegionFilter
    capPerThread?: number
}

interface RegionFilter {
    readable?: boolean
    writable?: boolean
    executable?: boolean
    tags?: number[] | Set<number>
    minBytes?: number
    maxBytes?: number
}
```

The lower-level `Scanner` class is also exported for callers that
want to feed in already-prepared buffers without going through the
`Target` abstraction.

## Building

The published package ships pre-built JavaScript and TypeScript
typings; you only need this section if you're modifying the assembly
core.

```sh
cd src
make            # builds scan_<arch>.dylib, regenerates ../lib/scanner/bytes-*.ts
make test       # native + Rosetta tests with perf numbers
```

The assembly sources, build scripts, and test harness live in `src/`
and are excluded from the npm package (only `dist/` ships).

## Platform support

| platform                     | status                                                  |
| ---------------------------- | ------------------------------------------------------- |
| Windows                      | stub (planned: `ReadProcessMemory` + `VirtualQueryEx`)  |
| macOS x86_64 (incl. Rosetta) | full — Mach backend                                     |
| macOS arm64 (incl. arm64e)   | full — Mach backend                                     |
| Linux                        | stub (planned: `process_vm_readv` + `/proc/<pid>/maps`) |

The scanner SIMD blob itself is platform-neutral; only the
cross-process VM access needs per-OS implementation.
