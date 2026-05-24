import { openProcessMemory } from "./process/index.js";
import { ProcessMemory, Region, RegionFilter } from "./process/types.js";
import { DEFAULT_ISA_MASK, Hit, Scanner } from "./scanner/index.js";
import { resolveTarget } from "./symbols.js";

export type TargetSpec = string | NativePointer | UInt64 | number;

export interface FindOpts {
    mask?: UInt64;
    filter?: RegionFilter;
    capPerThread?: number;
}

export interface ScanHit {
    addr: NativePointer;
    target: UInt64;
    region: { base: NativePointer; size: number; tag: number };
}

export class Target {
    readonly memory: ProcessMemory;
    #scanner: Scanner | null = null;

    static self(): Target {
        return new Target(openProcessMemory(Process.id));
    }

    static pid(pid: number): Target {
        return new Target(openProcessMemory(pid));
    }

    constructor(memory: ProcessMemory) {
        this.memory = memory;
    }

    find(targets: TargetSpec[], opts: FindOpts = {}): ScanHit[] {
        const mask = opts.mask ?? DEFAULT_ISA_MASK;
        const cap = opts.capPerThread ?? 1024;
        const filter = opts.filter ?? { readable: true };
        const targetVals = targets.map(normalizeTarget);
        const maskedTargets = targetVals.map(v => v.and(mask));
        const sc = this.#getScanner();
        const hits: ScanHit[] = [];

        for (const region of this.memory.regions(filter)) {
            const sz = region.size.toNumber();
            const buf = Memory.alloc(sz);
            if (!this.memory.readInto(region.base, buf, sz)) {
                continue;
            }
            const regionHits = sc.scanRemoteRegion(region.base, buf, sz, mask, targetVals, cap);
            const regionInfo = { base: region.base, size: sz, tag: region.tag };
            for (const h of regionHits) {
                hits.push({
                    addr: h.value,
                    target: pickMatchingTarget(maskedTargets, h.value.readU64().and(mask)),
                    region: regionInfo,
                });
            }
        }
        return hits;
    }

    read(addr: NativePointer, size: number): ArrayBuffer {
        const buf = this.memory.read(addr, size);
        if (buf === null) {
            throw new Error(`read(${addr}, ${size}) failed`);
        }
        return buf;
    }

    regions(filter?: RegionFilter): Iterable<Region> {
        return this.memory.regions(filter);
    }

    #getScanner(): Scanner {
        if (this.#scanner === null) {
            this.#scanner = new Scanner();
        }
        return this.#scanner;
    }
}

function normalizeTarget(t: TargetSpec): UInt64 {
    if (typeof t === "string") {
        return resolveTarget(t);
    }
    if (typeof t === "number") {
        return uint64(t);
    }
    if (t instanceof NativePointer) {
        return uint64(t.toString());
    }
    return t;
}

function pickMatchingTarget(maskedTargets: UInt64[], slot: UInt64): UInt64 {
    for (const t of maskedTargets) {
        if (t.compare(slot) === 0) {
            return t;
        }
    }
    return slot;
}
