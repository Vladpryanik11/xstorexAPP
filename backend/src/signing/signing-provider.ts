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
 * Stage 1: PreSignedProvider (the owner uploads IPAs already signed with their certificate).
 * Stage 2: a zsign-based adapter that re-signs the owner's own builds asynchronously
 * (returns `preparing`, the client polls GET /catalog/installs/{id}).
 */
export interface SigningProvider {
  readonly name: string;
  prepare(request: SigningRequest): Promise<SigningResult>;
}
