import { ProcessMemory, Region, RegionFilter } from "./types.js";

const UNIMPLEMENTED = "frida-mem-scan: Linux backend not yet implemented";

export class LinuxProcessMemory implements ProcessMemory {
    readonly pid: number;
    readonly isSelf: boolean;

    constructor(pid: number) {
        this.pid = pid;
        this.isSelf = pid === Process.id;
        throw new Error(UNIMPLEMENTED);
    }

    *regions(_filter?: RegionFilter): Iterable<Region> {
        throw new Error(UNIMPLEMENTED);
    }

    read(_addr: NativePointer, _size: number): ArrayBuffer | null {
        throw new Error(UNIMPLEMENTED);
    }

    readInto(_addr: NativePointer, _dst: NativePointer,
             _size: number): boolean {
        throw new Error(UNIMPLEMENTED);
    }
}
