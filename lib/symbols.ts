export function resolveTarget(t: string): UInt64 {
    if (!t.includes("!")) {
        return uint64(t);
    }
    const m = t.match(/^([^!]+)!([^+]+)(?:\+(0x[0-9a-fA-F]+|\d+))?$/);
    if (m === null) {
        throw new Error(`bad target spec: ${t}`);
    }
    const [, modName, symName, offStr] = m;
    let addr = Process.getModuleByName(modName).getSymbolByName(symName);
    if (offStr !== undefined) {
        const off = offStr.startsWith("0x") ? parseInt(offStr, 16) : parseInt(offStr, 10);
        addr = addr.add(off);
    }
    return uint64(addr.toString());
}
