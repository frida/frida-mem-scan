import { DarwinProcessMemory } from "./darwin.js";
import { LinuxProcessMemory } from "./linux.js";
import { ProcessMemory } from "./types.js";
import { WindowsProcessMemory } from "./windows.js";

export function openProcessMemory(pid: number): ProcessMemory {
    switch (Process.platform) {
        case "windows": return new WindowsProcessMemory(pid);
        case "darwin":  return new DarwinProcessMemory(pid);
        case "linux":   return new LinuxProcessMemory(pid);
        default:
            throw new Error(
                `frida-mem-scan: no backend for platform ${Process.platform}`);
    }
}
