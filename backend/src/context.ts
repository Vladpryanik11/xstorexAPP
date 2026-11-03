import type { AppConfig } from './config.js';
import type { Db } from './db/index.js';
import type { BlobStorage } from './storage/blob-storage.js';
import type { SigningProvider } from './signing/signing-provider.js';
import type { CatalogBus } from './modules/catalog/bus.js';

export interface AppContext {
  config: AppConfig;
  db: Db;
  storage: BlobStorage;
  signing: SigningProvider;
  bus: CatalogBus;
  now(): Date;
  /** Absolute URL for a stored asset (`icons/x.png`) or passthrough for http(s) URLs. */
  assetUrl(value: string): string;
  /** Absolute URL for an API path (`/api/v1/...`). */
  apiUrl(pathname: string): string;
}

export function createUrlHelpers(publicBaseUrl: string): Pick<AppContext, 'assetUrl' | 'apiUrl'> {
  return {
    assetUrl(value: string) {
      if (/^https?:\/\//i.test(value)) return value;
      const key = value.replace(/^\/+/, '').replace(/^static\//, '');
      return `${publicBaseUrl}/static/${key.split('/').map(encodeURIComponent).join('/')}`;
    },
    apiUrl(pathname: string) {
      return `${publicBaseUrl}${pathname.startsWith('/') ? '' : '/'}${pathname}`;
    },
  };
}
