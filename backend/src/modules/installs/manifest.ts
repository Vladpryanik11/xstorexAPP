import { buildXmlPlist } from '../../lib/plist.js';

export interface ManifestInput {
  ipaUrl: string;
  displayImageUrl: string;
  fullSizeImageUrl: string;
  bundleId: string;
  bundleVersion: string;
  title: string;
}

/** OTA manifest for `itms-services://?action=download-manifest`. */
export function buildManifest(m: ManifestInput): string {
  return buildXmlPlist({
    items: [
      {
        assets: [
          { kind: 'software-package', url: m.ipaUrl },
          { kind: 'display-image', url: m.displayImageUrl },
          { kind: 'full-size-image', url: m.fullSizeImageUrl },
        ],
        metadata: {
          'bundle-identifier': m.bundleId,
          'bundle-version': m.bundleVersion,
          kind: 'software',
          title: m.title,
        },
      },
    ],
  });
}
