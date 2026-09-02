import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { shouldApplyCenterMembershipRefresh } from './membershipRefresh.ts';

describe('center membership refresh sequencing', () => {
  it('applies the latest in-focus response', () => {
    assert.equal(shouldApplyCenterMembershipRefresh(2, 2, true), true);
  });

  it('does not let an older request overwrite a newer one', () => {
    assert.equal(shouldApplyCenterMembershipRefresh(1, 2, true), false);
  });

  it('does not apply a completed request after screen blur', () => {
    assert.equal(shouldApplyCenterMembershipRefresh(1, 1, false), false);
  });

  it('does not let an older finally clear loading while a newer request is active', () => {
    assert.equal(shouldApplyCenterMembershipRefresh(1, 2, true), false);
    assert.equal(shouldApplyCenterMembershipRefresh(2, 2, true), true);
  });

  it('allows retry as a newer in-focus request', () => {
    assert.equal(shouldApplyCenterMembershipRefresh(3, 3, true), true);
  });
});
