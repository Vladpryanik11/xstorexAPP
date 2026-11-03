export interface SigningRequest {
  installId: string;
  appId: string;
  build: {
    id: string;
    blobKey: string;
    bundleId: string | null;
    version: string;
    sizeBytes: number;
    sha256: string | null;
  };
}

export type SigningResult =
  | { status: 'ready'; blobKey: string; sizeBytes: number; sha256: string | null }
  | { status: 'preparing' }
  | { status: 'failed'; errorCode: string };

/**
 * Produces an installable IPA for a grant.
 * Current implementation: PreSignedProvider returns an already uploaded IPA without signing it.
 * Required next: server-side signing and re-signing for uploaded IPA files, including
 * third-party and modified builds, with device/profile selection and asynchronous processing.
 * The client can poll GET /catalog/installs/{id} while status is `preparing`.
 */
export interface SigningProvider {
  readonly name: string;
  prepare(request: SigningRequest): Promise<SigningResult>;
}
