import {
  listMyEquineManagementAssignments,
  listMyEquineOwnerships,
} from '../equines/ownershipService';
import { supabase } from '../../services/supabase/client';
import { VerificationResponseError } from './verificationErrors';
import {
  parseIdentityCaseRows,
  parseVerificationStatusRows,
} from './verificationRow';
import { SPAIN_MARKET, type VerificationSnapshot } from './types';

async function equineNames(): Promise<Map<string, string>> {
  const names = new Map<string, string>();

  try {
    const [ownerships, assignments] = await Promise.all([
      listMyEquineOwnerships(),
      listMyEquineManagementAssignments(),
    ]);

    for (const ownership of ownerships) {
      names.set(ownership.equineId, ownership.equineName);
    }

    for (const assignment of assignments) {
      if (!names.has(assignment.equineId)) {
        names.set(assignment.equineId, assignment.equineName);
      }
    }
  } catch {
    return new Map();
  }

  return names;
}

export async function loadMyVerification(): Promise<VerificationSnapshot> {
  const [statusResult, casesResult] = await Promise.all([
    supabase.rpc('list_my_verification_status'),
    supabase.rpc('list_my_identity_cases'),
  ]);

  if (statusResult.error) {
    throw statusResult.error;
  }

  if (casesResult.error) {
    throw casesResult.error;
  }

  return {
    statusRows: parseVerificationStatusRows(statusResult.data ?? []),
    identityCases: parseIdentityCaseRows(casesResult.data ?? []),
    equineNames: await equineNames(),
  };
}

export async function submitSpainIdentityCase(): Promise<void> {
  const { data, error } = await supabase.rpc('submit_my_identity_case', {
    p_market_country_code: SPAIN_MARKET,
  });

  if (error) {
    throw error;
  }

  const rows = parseIdentityCaseRows(
    (Array.isArray(data) ? data : []).map((row) => {
      if (!row || typeof row !== 'object') {
        return row;
      }

      const record = row as Record<string, unknown>;
      return {
        case_id: record.case_id,
        state: record.state,
        market_country_code: record.market_country_code,
        outcome: null,
        decided_at: null,
      };
    }),
  );

  if (
    rows.length !== 1 ||
    rows[0]?.marketCountryCode !== SPAIN_MARKET ||
    rows[0]?.state !== 'SUBMITTED'
  ) {
    throw new VerificationResponseError();
  }
}
