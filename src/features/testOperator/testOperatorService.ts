import type { ActivityBooking } from '../activity/types';
import { supabase } from '../../services/supabase/client';

export type TestWorkspaceRow = {
  kind: 'CENTER' | 'EQUINE' | 'SERVICE';
  entityId: string;
  label: string;
};

export type AuthorizedActivityResult = {
  bookingId: string;
  equineName: string;
  centerName: string;
  startsAt: string;
  endsAt: string;
  bookingStatus: ActivityBooking['bookingStatus'];
  sessionStatus: string | null;
  callerRelation: 'PARTICIPANT' | 'BOOKER' | 'VIEW_ACTIVITY';
};

function messageFrom(error: unknown): string {
  if (error && typeof error === 'object' && 'message' in error) {
    const message = error.message;
    if (typeof message === 'string' && message.length > 0) {
      return message;
    }
  }
  return 'No se ha podido completar la operación de prueba.';
}

export function testOperatorErrorMessage(error: unknown): string {
  return messageFrom(error);
}

async function call(name: string, args?: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await supabase.rpc(name, args);
  if (error) {
    throw error;
  }
  return data;
}

export async function testOperatorAvailable(): Promise<boolean> {
  const data = await call('test_operator_available');
  return data === true;
}

export async function listTestWorkspace(): Promise<TestWorkspaceRow[]> {
  const data = await call('list_test_operator_workspace');
  if (!Array.isArray(data)) {
    return [];
  }
  return data.flatMap((row) => {
    if (!row || typeof row !== 'object') {
      return [];
    }
    const record = row as Record<string, unknown>;
    const kind = record.kind;
    const entityId = record.entity_id;
    const label = record.label;
    if (
      (kind !== 'CENTER' && kind !== 'EQUINE' && kind !== 'SERVICE') ||
      typeof entityId !== 'string' ||
      typeof label !== 'string'
    ) {
      return [];
    }
    return [{ kind, entityId, label }];
  });
}

export function createTestCenter(name: string, timezone: string): Promise<unknown> {
  return call('create_test_center', { p_name: name, p_timezone: timezone });
}

export function assignTestCenterRole(
  centerId: string,
  email: string,
  roleCode: string,
): Promise<unknown> {
  return call('assign_test_center_role', {
    p_center_id: centerId,
    p_email: email,
    p_role_code: roleCode,
  });
}

export function registerTestEquine(equineId: string): Promise<unknown> {
  return call('register_test_equine', { p_equine_id: equineId });
}

export function assignTestEquine(
  equineId: string,
  centerId: string,
  assignmentType: string,
): Promise<unknown> {
  return call('assign_test_equine_to_center', {
    p_equine_id: equineId,
    p_center_id: centerId,
    p_assignment_type: assignmentType,
  });
}

export function grantTestPermission(
  equineId: string,
  centerId: string,
  permissionCode: string,
): Promise<unknown> {
  return call('grant_test_equine_permission', {
    p_equine_id: equineId,
    p_center_id: centerId,
    p_permission_code: permissionCode,
  });
}

export function createTestService(
  centerId: string,
  name: string,
  durationMinutes: number,
): Promise<unknown> {
  return call('create_test_service', {
    p_center_id: centerId,
    p_name: name,
    p_duration_minutes: durationMinutes,
  });
}

export function linkTestService(serviceId: string, equineId: string): Promise<unknown> {
  return call('link_test_service_equine', {
    p_service_id: serviceId,
    p_equine_id: equineId,
  });
}

export function setTestAvailability(
  equineId: string,
  centerId: string,
  startsAt: string,
  endsAt: string,
): Promise<unknown> {
  return call('set_test_availability', {
    p_equine_id: equineId,
    p_center_id: centerId,
    p_starts_at: startsAt,
    p_ends_at: endsAt,
  });
}

export function addTestBlock(
  equineId: string,
  centerId: string,
  startsAt: string,
  endsAt: string,
  blockType: string,
): Promise<unknown> {
  return call('add_test_calendar_block', {
    p_equine_id: equineId,
    p_center_id: centerId,
    p_starts_at: startsAt,
    p_ends_at: endsAt,
    p_block_type: blockType,
  });
}

export function markTestVisibility(equineId: string, visibility: 'PUBLIC' | 'PRIVATE'): Promise<unknown> {
  return call('mark_test_equine_visibility', {
    p_equine_id: equineId,
    p_visibility: visibility,
  });
}

export function openTestPilot(
  pilotCode: string,
  centerId: string,
  equineId: string,
): Promise<unknown> {
  return call('open_test_bookable_pilot', {
    p_pilot_code: pilotCode,
    p_center_id: centerId,
    p_equine_id: equineId,
  });
}

export function transferTestManager(equineId: string, email: string): Promise<unknown> {
  return call('transfer_test_primary_manager', {
    p_equine_id: equineId,
    p_email: email,
  });
}

export function transferTestOwnership(equineId: string, email: string): Promise<unknown> {
  return call('transfer_test_person_ownership', {
    p_equine_id: equineId,
    p_email: email,
  });
}

export function retireTestOperatorData(): Promise<unknown> {
  return call('retire_test_operator_data');
}

export async function listAuthorizedActivityResults(): Promise<AuthorizedActivityResult[]> {
  const data = await call('list_authorized_activity_results');
  if (!Array.isArray(data)) {
    return [];
  }
  return data.flatMap((row) => {
    if (!row || typeof row !== 'object') {
      return [];
    }
    const record = row as Record<string, unknown>;
    const relation = record.caller_relation;
    const status = record.booking_status;
    const knownStatus =
      status === 'DRAFT' ||
      status === 'REQUESTED' ||
      status === 'PENDING_REQUIREMENTS' ||
      status === 'PENDING_APPROVAL' ||
      status === 'APPROVED' ||
      status === 'CONFIRMED' ||
      status === 'ACTIVE' ||
      status === 'COMPLETED' ||
      status === 'REJECTED' ||
      status === 'CANCELLED' ||
      status === 'EXPIRED' ||
      status === 'DISPUTED';
    if (
      typeof record.booking_id !== 'string' ||
      typeof record.equine_name !== 'string' ||
      typeof record.center_name !== 'string' ||
      typeof record.starts_at !== 'string' ||
      typeof record.ends_at !== 'string' ||
      !knownStatus ||
      (relation !== 'PARTICIPANT' && relation !== 'BOOKER' && relation !== 'VIEW_ACTIVITY')
    ) {
      return [];
    }
    return [
      {
        bookingId: record.booking_id,
        equineName: record.equine_name,
        centerName: record.center_name,
        startsAt: record.starts_at,
        endsAt: record.ends_at,
        bookingStatus: status,
        sessionStatus:
          typeof record.session_status === 'string' ? record.session_status : null,
        callerRelation: relation,
      },
    ];
  });
}
