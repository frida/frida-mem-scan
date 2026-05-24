import { ProcessMemory, Region, RegionFilter } from "./types.js";

const KERN_SUCCESS = 0;
const VM_PROT_EXEC = 0x04;
const VM_PROT_READ = 0x01;
const VM_PROT_WRITE = 0x02;
const VM_REGION_INFO_COUNT = 19;

export class DarwinProcessMemory implements ProcessMemory {
    readonly pid: number;
    readonly isSelf: boolean;
    #task: number;

    constructor(pid: number) {
        resolveNatives();
        this.pid = pid;
        this.isSelf = pid === Process.id;
        this.#task = openTask(pid);
    }

    *regions(filter?: RegionFilter): Iterable<Region> {
        const wantReadable = filter?.readable === true;
        const wantWritable = filter?.writable === true;
        const wantExecutable = filter?.executable === true;
        const tagSet = makeTagSet(filter?.tags);
        const minBytes = filter?.minBytes;
        const maxBytes = filter?.maxBytes;

        let cursor = NULL;
        while (true) {
            const r = nextRegion(this.#task, cursor);
            if (r === null) {
                break;
            }
            cursor = r.base.add(r.size);

            if (wantReadable && !r.readable) {
                continue;
            }
            if (wantWritable && !r.writable) {
                continue;
            }
            if (wantExecutable && !r.executable) {
                continue;
            }
            if (tagSet !== null && !tagSet.has(r.tag)) {
                continue;
            }
            const sz = r.size.toNumber();
            if (minBytes !== undefined && sz < minBytes) {
                continue;
            }
            if (maxBytes !== undefined && sz > maxBytes) {
                continue;
            }

            yield r;
        }
    }

    read(addr: NativePointer, size: number): ArrayBuffer | null {
        const buf = Memory.alloc(size);
        if (!this.readInto(addr, buf, size)) {
            return null;
        }
        const view = new Uint8Array(buf.readByteArray(size) as ArrayBuffer);
        return view.slice().buffer;
    }

    readInto(addr: NativePointer, dst: NativePointer, size: number): boolean {
        const outsize = Memory.alloc(8);
        const kr = machVmReadOverwrite!(this.#task, addr, uint64(size), dst, outsize);
        return kr === KERN_SUCCESS;
    }
}

function makeTagSet(tags: RegionFilter["tags"]): Set<number> | null {
    if (tags === undefined) {
        return null;
    }
    return tags instanceof Set ? tags : new Set(tags);
}

function openTask(pid: number): number {
    if (pid === Process.id) {
        return machTaskSelf;
    }
    const out = Memory.alloc(4);
    const kr = taskForPid!(machTaskSelf, pid, out);
    if (kr !== KERN_SUCCESS) {
        throw new Error(`task_for_pid(${pid}) failed: kr=${kr}`);
    }
    return out.readU32();
}

function nextRegion(task: number, startAddr: NativePointer): Region | null {
    const ADDR_OFF = 0;
    const SIZE_OFF = 8;
    const DEPTH_OFF = 16;
    const INFO_OFF = 24;
    const COUNT_OFF = 152;
    const TOTAL = 156;

    const scratch = Memory.alloc(TOTAL);
    const addrPtr = scratch.add(ADDR_OFF);
    const sizePtr = scratch.add(SIZE_OFF);
    const depthPtr = scratch.add(DEPTH_OFF);
    const info = scratch.add(INFO_OFF);
    const countPtr = scratch.add(COUNT_OFF);

    addrPtr.writePointer(startAddr);
    depthPtr.writeU32(2048);
    countPtr.writeU32(VM_REGION_INFO_COUNT);

    const kr = machVmRegionRecurse!(task, addrPtr, sizePtr, depthPtr, info, countPtr);
    if (kr !== KERN_SUCCESS) {
        return null;
    }

    const prot = info.readS32();
    return {
        base: addrPtr.readPointer(),
        size: sizePtr.readU64(),
        readable:   (prot & VM_PROT_READ)  !== 0,
        writable:   (prot & VM_PROT_WRITE) !== 0,
        executable: (prot & VM_PROT_EXEC)  !== 0,
        tag: info.add(24).readU32(),
    };
}

let machTaskSelf = 0;
let machVmReadOverwrite: NativeFunction<number, [number, NativePointer, UInt64, NativePointer, NativePointer]> | null = null;
let machVmRegionRecurse: NativeFunction<number, [number, NativePointer, NativePointer, NativePointer, NativePointer, NativePointer]> | null = null;
let taskForPid: NativeFunction<number, [number, number, NativePointer]> | null = null;

function resolveNatives(): void {
    if (taskForPid !== null) {
        return;
    }
    const libSystem = Process.getModuleByName("libSystem.B.dylib");
    machTaskSelf = libSystem.getExportByName("mach_task_self_").readU32();
    taskForPid = new NativeFunction(libSystem.getExportByName("task_for_pid"),
        "int", ["uint", "int", "pointer"]);
    machVmRegionRecurse = new NativeFunction(libSystem.getExportByName("mach_vm_region_recurse"),
        "int", ["uint", "pointer", "pointer", "pointer", "pointer", "pointer"]);
    machVmReadOverwrite = new NativeFunction(libSystem.getExportByName("mach_vm_read_overwrite"),
        "int", ["uint", "pointer", "uint64", "pointer", "pointer"]);
}
