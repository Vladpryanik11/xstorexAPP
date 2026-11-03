import type { SigningProvider, SigningRequest, SigningResult } from './signing-provider.js';

/** Existing mode: return an uploaded IPA as-is. This provider does not sign or validate its code signature. */
export class PreSignedProvider implements SigningProvider {
  readonly name = 'presigned';

  async prepare(request: SigningRequest): Promise<SigningResult> {
    return {
      status: 'ready',
      blobKey: request.build.blobKey,
      sizeBytes: request.build.sizeBytes,
      sha256: request.build.sha256,
    };
  }
}
