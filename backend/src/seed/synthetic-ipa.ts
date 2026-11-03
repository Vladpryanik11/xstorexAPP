import { zipSync, type Zippable } from 'fflate';
import { build as buildXml, buildBinary } from 'plist';

export interface SyntheticIpaOptions {
  bundleId: string;
  version: string;
  build: string;
  name: string;
  minOs?: string;
  /** Binary (bplist00) Info.plist instead of XML. */
  binaryPlist?: boolean;
  /** Incompressible filler to make the archive a realistic size. */
  padBytes?: number;
  appDir?: string;
}

function filler(size: number, seed: number): Uint8Array {
  const out = new Uint8Array(size);
  let x = seed >>> 0 || 0x9e3779b9;
  for (let i = 0; i < size; i += 1) {
    x ^= x << 13;
    x ^= x >>> 17;
    x ^= x << 5;
    out[i] = x & 0xff;
  }
  return out;
}

/**
 * A minimal zip that looks like an IPA (`Payload/Demo.app/Info.plist`).
 * It is NOT installable on a device — it only exercises upload, parsing and the OTA path.
 */
export function buildSyntheticIpa(o: SyntheticIpaOptions): Uint8Array {
  const info = {
    CFBundleIdentifier: o.bundleId,
    CFBundleShortVersionString: o.version,
    CFBundleVersion: o.build,
    CFBundleName: o.name,
    CFBundleDisplayName: o.name,
    CFBundleExecutable: 'Demo',
    CFBundlePackageType: 'APPL',
    MinimumOSVersion: o.minOs ?? '15.0',
  };
  const plist = o.binaryPlist ? buildBinary(info) : new TextEncoder().encode(buildXml(info));
  const dir = `Payload/${o.appDir ?? 'Demo.app'}`;
  const files: Zippable = {
    [`${dir}/Info.plist`]: plist,
    [`${dir}/PkgInfo`]: new TextEncoder().encode('APPL????'),
  };
  if (o.padBytes && o.padBytes > 0) files[`${dir}/Demo`] = [filler(o.padBytes, o.bundleId.length * 7919), { level: 0 }];
  return zipSync(files, { level: 6 });
}
