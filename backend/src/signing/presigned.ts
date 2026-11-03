import type { SigningProvider, SigningRequest, SigningResult } from './signing-provider.js';

/** The uploaded IPA is already signed by the store owner: the grant is ready immediately. */
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
