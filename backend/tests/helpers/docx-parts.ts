import { crc32, inflateRawSync } from 'node:zlib';

/** Independent ZIP-directory reader for assertions; validates CRC and lengths. */
export function docxParts(zip: Buffer): Map<string, Buffer> {
  const end = zip.length - 22;
  if (zip.readUInt32LE(end) !== 0x06054b50) throw new Error('Missing ZIP directory');
  const parts = new Map<string, Buffer>();
  let cursor = zip.readUInt32LE(end + 16);
  for (let i = 0; i < zip.readUInt16LE(end + 10); i++) {
    if (zip.readUInt32LE(cursor) !== 0x02014b50) throw new Error('Invalid ZIP entry');
    const length = zip.readUInt16LE(cursor + 28);
    const name = zip.subarray(cursor + 46, cursor + 46 + length).toString();
    const local = zip.readUInt32LE(cursor + 42);
    if (zip.readUInt32LE(local) !== 0x04034b50) throw new Error('Invalid local entry');
    const start = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28);
    const packed = zip.subarray(start, start + zip.readUInt32LE(cursor + 20));
    const method = zip.readUInt16LE(cursor + 10);
    if (method !== 0 && method !== 8) throw new Error('Unsupported ZIP method');
    const bytes = method === 0 ? packed : inflateRawSync(packed);
    if (crc32(bytes) !== zip.readUInt32LE(cursor + 16) || bytes.length !== zip.readUInt32LE(cursor + 24)) {
      throw new Error('Corrupt ZIP content');
    }
    parts.set(name, bytes);
    cursor += 46 + length + zip.readUInt16LE(cursor + 30) + zip.readUInt16LE(cursor + 32);
  }
  return parts;
}
