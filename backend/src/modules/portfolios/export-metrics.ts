import { performance } from 'node:perf_hooks';
export type ExportObserver = (stage: string, milliseconds: number) => void;
/** Opt-in local benchmark hook: no identifiers, prose, tokens or automatic logs. */
export async function measureExport<T>(stage: string, observer: ExportObserver | undefined, action: () => T | Promise<T>): Promise<T> {
  const start = performance.now();
  try { return await action(); } finally { observer?.(stage, performance.now() - start); }
}
