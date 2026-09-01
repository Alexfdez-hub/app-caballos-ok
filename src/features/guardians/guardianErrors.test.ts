import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { userFacingGuardianMessage } from './guardianErrors.ts';

describe('userFacingGuardianMessage', () => {
  it('distinguishes missing guardian policy from generic failures', () => {
    assert.equal(
      userFacingGuardianMessage({
        message: 'Required guardian policy has not been accepted',
      }),
      'Falta aceptar la política de tutor. Eso es distinto del consentimiento de actividad.',
    );
  });

  it('explains unverified relationships', () => {
    assert.equal(
      userFacingGuardianMessage({
        message: 'Guardian relationship is not verified and active',
      }),
      'Esta relación no está verificada, así que no se puede conceder consentimiento.',
    );
  });
});
