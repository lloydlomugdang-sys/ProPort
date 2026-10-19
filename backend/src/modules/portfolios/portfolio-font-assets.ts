import { readFile } from 'node:fs/promises';
// Only immutable licensed assets are cached; no owner/evidence data crosses requests.
const fonts = new Map<boolean, Promise<Buffer>>();
export function portfolioFontBytes(bold: boolean): Promise<Buffer> {
  let pending = fonts.get(bold);
  if (!pending) {
    const name = `NotoSans-${bold ? 'Bold' : 'Regular'}.ttf`;
    pending = readFile(new URL(`../../../../assets/fonts/${name}`, import.meta.url))
      .catch(() => readFile(new URL(`../../../../../assets/fonts/${name}`, import.meta.url)));
    fonts.set(bold, pending);
    void pending.catch(() => fonts.delete(bold));
  }
  return pending;
}
