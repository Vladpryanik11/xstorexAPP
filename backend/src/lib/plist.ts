import { parse as parseXmlPlist, parseBinary } from 'plist';

export type PlistNode = string | number | boolean | PlistNode[] | { [key: string]: PlistNode };

// Characters not allowed in XML 1.0 documents.
// eslint-disable-next-line no-control-regex
const INVALID_XML_CHARS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F￾￿]/g;

export function escapeXml(value: string): string {
  return value
    .replace(INVALID_XML_CHARS, '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function serialize(node: PlistNode, depth: number, out: string[]): void {
  const pad = '\t'.repeat(depth);
  if (typeof node === 'string') {
    out.push(`${pad}<string>${escapeXml(node)}</string>`);
  } else if (typeof node === 'number') {
    if (!Number.isFinite(node)) throw new RangeError('plist numbers must be finite');
    out.push(Number.isInteger(node) ? `${pad}<integer>${node}</integer>` : `${pad}<real>${node}</real>`);
  } else if (typeof node === 'boolean') {
    out.push(`${pad}<${node ? 'true' : 'false'}/>`);
  } else if (Array.isArray(node)) {
    if (node.length === 0) {
      out.push(`${pad}<array/>`);
      return;
    }
    out.push(`${pad}<array>`);
    for (const item of node) serialize(item, depth + 1, out);
    out.push(`${pad}</array>`);
  } else {
    const entries = Object.entries(node);
    if (entries.length === 0) {
      out.push(`${pad}<dict/>`);
      return;
    }
    out.push(`${pad}<dict>`);
    for (const [key, value] of entries) {
      out.push(`${pad}\t<key>${escapeXml(key)}</key>`);
      serialize(value, depth + 1, out);
    }
    out.push(`${pad}</dict>`);
  }
}

/** Serializes a value as an XML property list (Apple DTD 1.0). */
export function buildXmlPlist(root: PlistNode): string {
  const out = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
  ];
  serialize(root, 0, out);
  out.push('</plist>', '');
  return out.join('\n');
}

/** Parses an Info.plist that may be binary (`bplist00`) or XML. */
export function parsePlistBuffer(buf: Uint8Array): unknown {
  const head = Buffer.from(buf.buffer, buf.byteOffset, Math.min(buf.byteLength, 8)).toString('latin1');
  if (head.startsWith('bplist')) return parseBinary(buf);
  return parseXmlPlist(Buffer.from(buf.buffer, buf.byteOffset, buf.byteLength).toString('utf8'));
}
