import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import {
  parseMyEquineDetail,
  parseMyEquineSummary,
  userFacingEquineCreateMessage,
} from './equineCreate.ts';

const summary = {
  equine_id: '03110000-0000-4000-8000-0000000000aa',
  equine_name: 'Nube',
  equine_type: 'HORSE',
  status: 'ACTIVE',
  visibility_status: 'PRIVATE',
  is_owner: true,
  is_primary_manager: true,
};

describe('equine create parsing', () => {
  it('accepts a caller-scoped summary', () => {
    assert.equal(parseMyEquineSummary(summary).equineName, 'Nube');
  });

  it('fails closed on a public visibility that is not a known token', () => {
    assert.throws(() =>
      parseMyEquineSummary({ ...summary, visibility_status: 'OPEN' }),
    );
  });

  it('accepts detail height encoded as text and rejects a bad height', () => {
    const detail = parseMyEquineDetail({
      ...summary,
      birth_date: null,
      sex: null,
      breed: null,
      height_cm: '152.5',
      description: null,
      temperament_description: null,
    });
    assert.equal(detail.heightCm, 152.5);
    assert.throws(() =>
      parseMyEquineDetail({
        ...summary,
        birth_date: null,
        sex: null,
        breed: null,
        height_cm: 'tall',
        description: null,
        temperament_description: null,
      }),
    );
  });
});

describe('equine create errors', () => {
  it('does not echo a database error', () => {
    assert.equal(
      userFacingEquineCreateMessage({
        message: 'duplicate key value violates unique constraint secret',
      }),
      'No se pudo completar la acción del equino. Inténtalo de nuevo.',
    );
    assert.match(
      userFacingEquineCreateMessage({
        message: 'Equine creation is not available',
      }),
      /edad o el mercado/,
    );
  });
});
