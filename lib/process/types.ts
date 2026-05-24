export interface Region {
    base: NativePointer;
    size: UInt64;
    readable: boolean;
    writable: boolean;
    executable: boolean;
    // Platform-defined region tag (0 = none). Darwin: VM_MEMORY_*.
    tag: number;
}

export interface RegionFilter {
    readable?: boolean;
    writable?: boolean;
    executable?: boolean;
    tags?: number[] | Set<number>;
    minBytes?: number;
    maxBytes?: number;
}

export interface ProcessMemory {
    readonly pid: number;
    readonly isSelf: boolean;
    regions(filter?: RegionFilter): Iterable<Region>;
    read(addr: NativePointer, size: number): ArrayBuffer | null;
    readInto(addr: NativePointer, dst: NativePointer,
             size: number): boolean;
}
