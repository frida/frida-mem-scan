import { SCAN_ARM64_BYTES, SYMBOLS as SYMBOLS_ARM64 } from "./bytes-arm64.js";
import { SCAN_X86_64_BYTES, SYMBOLS as SYMBOLS_X86_64 } from "./bytes-x86_64.js";

export interface Hit {
    value: NativePointer;
    index: number;
}

// arm64e PAC + non-pointer-isa bits masked off; leaves bits 3..47.
export const DEFAULT_ISA_MASK = uint64("0x00007ffffffffff8");

const PARALLEL_THRESHOLD_BYTES = 4 * 1024 * 1024;
const QOS_CLASS_USER_INITIATED = 0x21;

export class Scanner {
    #scan: NativeFunction<UInt64, [NativePointer, UInt64, UInt64, NativePointer, UInt64, NativePointer, UInt64]>;
    #scan1: NativeFunction<UInt64, [NativePointer, UInt64, UInt64, UInt64, NativePointer, UInt64]>;
    #scanParallel: NativeFunction<void, [NativePointer, NativePointer, NativePointer, UInt64, UInt64, NativePointer, UInt64, NativePointer, UInt64, NativePointer, NativePointer, UInt64]>;
    #scan1Parallel: NativeFunction<void, [NativePointer, NativePointer, NativePointer, UInt64, UInt64, UInt64, NativePointer, UInt64, NativePointer, NativePointer, UInt64]>;
    #dispatchApplyF: NativePointer;
    #queue: NativePointer;
    #nthreads: number;
    // Pin the JIT page so the runtime doesn't reclaim it while the
    // NativeFunction descriptors below still hold raw pointers into it.
    #code: NativePointer;

    constructor(nthreads?: number) {
        const blob = selectBlob();
        this.#code = Memory.alloc(Math.max(blob.bytes.byteLength, Process.pageSize));
        Memory.patchCode(this.#code, blob.bytes.byteLength, (dst) => {
            dst.writeByteArray(blob.bytes.buffer as ArrayBuffer);
        });

        this.#scan = new NativeFunction(this.#code.add(blob.symbols.scan), "uint64",
            ["pointer", "uint64", "uint64", "pointer", "uint64", "pointer", "uint64"]) as any;
        this.#scan1 = new NativeFunction(this.#code.add(blob.symbols.scan1), "uint64",
            ["pointer", "uint64", "uint64", "uint64", "pointer", "uint64"]) as any;
        this.#scanParallel = new NativeFunction(this.#code.add(blob.symbols.scan_parallel), "void",
            ["pointer", "pointer", "pointer", "uint64", "uint64", "pointer", "uint64", "pointer", "uint64",
             "pointer", "pointer", "uint64"]) as any;
        this.#scan1Parallel = new NativeFunction(this.#code.add(blob.symbols.scan1_parallel), "void",
            ["pointer", "pointer", "pointer", "uint64", "uint64", "uint64", "pointer", "uint64",
             "pointer", "pointer", "uint64"]) as any;

        const libSystem = Process.getModuleByName("libSystem.B.dylib");
        this.#dispatchApplyF = libSystem.getExportByName("dispatch_apply_f");
        const getQueue = new NativeFunction(libSystem.getExportByName("dispatch_get_global_queue"),
            "pointer", ["long", "ulong"]);
        this.#queue = getQueue(QOS_CLASS_USER_INITIATED, 0) as NativePointer;

        this.#nthreads = hwThreadCount(libSystem, nthreads);
    }

    scanRemoteRegion(remoteBase: NativePointer, localBuf: NativePointer, byteLen: number,
                     mask: UInt64, targets: (UInt64 | number)[], capPerThread = 1024): Hit[] {
        const qcount = Math.floor(byteLen / 8);
        const localHits = this.scanLocal(localBuf, qcount, mask, targets, capPerThread);
        return localHits.map(h => ({
            value: remoteBase.add(h.index * 8),
            index: h.index,
        }));
    }

    scanLocal(buf: NativePointer, qcount: number | UInt64, mask: UInt64,
              targets: (UInt64 | number)[], capPerThread = 1024): Hit[] {
        const qc = uint64(qcount as any);
        const small = qc.toNumber() * 8 < PARALLEL_THRESHOLD_BYTES;

        if (targets.length === 1) {
            const target = uint64(targets[0] as any).and(mask);
            if (small) {
                return this.#runScan1Single(buf, qc, mask, target, capPerThread);
            }
            return this.#runScan1Parallel(buf, qc, mask, target, capPerThread);
        }

        const targetsMem = packTargets(targets, mask);
        if (small) {
            return this.#runScanSingle(buf, qc, mask, targetsMem, targets.length, capPerThread);
        }
        return this.#runScanParallel(buf, qc, mask, targetsMem, targets.length, capPerThread);
    }

    #runScan1Single(buf: NativePointer, qc: UInt64, mask: UInt64, target: UInt64, cap: number): Hit[] {
        const out = Memory.alloc(cap * 4);
        const hits = (this.#scan1(buf, qc, mask, target, out, uint64(cap)) as UInt64).toNumber();
        return readHits(buf, out, Math.min(hits, cap), 0);
    }

    #runScan1Parallel(buf: NativePointer, qc: UInt64, mask: UInt64, target: UInt64,
                      capPerThread: number): Hit[] {
        const nthreads = this.#nthreads;
        const scratch = allocScratch(nthreads, capPerThread);
        this.#scan1Parallel(this.#dispatchApplyF, this.#queue, buf, qc, mask, target,
            scratch.outFlat, uint64(capPerThread), scratch.counts, scratch.offs, uint64(nthreads));
        return collectHits(buf, scratch.outFlat, scratch.counts, scratch.offs, nthreads, capPerThread);
    }

    #runScanSingle(buf: NativePointer, qc: UInt64, mask: UInt64, targetsMem: NativePointer,
                   ntargets: number, cap: number): Hit[] {
        const out = Memory.alloc(cap * 4);
        const hits = (this.#scan(buf, qc, mask, targetsMem, uint64(ntargets), out,
            uint64(cap)) as UInt64).toNumber();
        return readHits(buf, out, Math.min(hits, cap), 0);
    }

    #runScanParallel(buf: NativePointer, qc: UInt64, mask: UInt64, targetsMem: NativePointer,
                     ntargets: number, capPerThread: number): Hit[] {
        const nthreads = this.#nthreads;
        const scratch = allocScratch(nthreads, capPerThread);
        this.#scanParallel(this.#dispatchApplyF, this.#queue, buf, qc, mask, targetsMem,
            uint64(ntargets), scratch.outFlat, uint64(capPerThread), scratch.counts, scratch.offs,
            uint64(nthreads));
        return collectHits(buf, scratch.outFlat, scratch.counts, scratch.offs, nthreads, capPerThread);
    }
}

interface ParallelScratch {
    outFlat: NativePointer;
    counts: NativePointer;
    offs: NativePointer;
}

function allocScratch(nthreads: number, capPerThread: number): ParallelScratch {
    const outFlatBytes = nthreads * capPerThread * 4;
    const countsBytes = nthreads * 8;
    const offsBytes = nthreads * 8;
    const scratch = Memory.alloc(outFlatBytes + countsBytes + offsBytes);
    return {
        outFlat: scratch,
        counts:  scratch.add(outFlatBytes),
        offs:    scratch.add(outFlatBytes + countsBytes),
    };
}

function packTargets(targets: (UInt64 | number)[], mask: UInt64): NativePointer {
    const mem = Memory.alloc(Math.max(1, targets.length) * 8);
    for (let i = 0; i !== targets.length; i++) {
        const masked = uint64(targets[i] as any).and(mask);
        mem.add(i * 8).writeU64(masked);
    }
    return mem;
}

function collectHits(buf: NativePointer, outFlat: NativePointer, counts: NativePointer,
                     offs: NativePointer, nthreads: number, capPerThread: number): Hit[] {
    const hits: Hit[] = [];
    for (let i = 0; i !== nthreads; i++) {
        const count = counts.add(i * 8).readU64().toNumber();
        const chunkOff = offs.add(i * 8).readU64().toNumber();
        const base = outFlat.add(i * capPerThread * 4);
        hits.push(...readHits(buf, base, Math.min(count, capPerThread), chunkOff));
    }
    return hits;
}

function readHits(buf: NativePointer, out: NativePointer, n: number, chunkOff: number): Hit[] {
    const hits: Hit[] = [];
    for (let j = 0; j !== n; j++) {
        const index = chunkOff + out.add(j * 4).readU32();
        hits.push({ value: buf.add(index * 8), index });
    }
    return hits;
}

interface Blob {
    bytes: Uint8Array;
    symbols: Record<string, number>;
}

function selectBlob(): Blob {
    if (Process.arch === "x64") {
        return { bytes: SCAN_X86_64_BYTES, symbols: SYMBOLS_X86_64 };
    }
    if (Process.arch === "arm64") {
        return { bytes: SCAN_ARM64_BYTES, symbols: SYMBOLS_ARM64 };
    }
    throw new Error(`frida-mem-scan: unsupported arch ${Process.arch}`);
}

function hwThreadCount(libSystem: Module, override?: number): number {
    if (override !== undefined) {
        return override;
    }
    const sysctlbyname = new NativeFunction(libSystem.getExportByName("sysctlbyname"),
        "int", ["pointer", "pointer", "pointer", "pointer", "size_t"]);
    const name = Memory.allocUtf8String("hw.logicalcpu");
    const out = Memory.alloc(4);
    const len = Memory.alloc(8);
    len.writeU64(4);
    sysctlbyname(name, out, len, NULL, 0);
    return out.readU32();
}
