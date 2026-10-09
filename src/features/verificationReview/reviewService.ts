import { supabase } from '../../services/supabase/client';
import {
  parseReviewCapabilities,
  parseReviewCase,
  parseReviewQueue,
} from './reviewRow';
import type { ReviewCapability, ReviewCaseDetail, ReviewQueueItem } from './types';

export async function loadReviewCapabilities(): Promise<ReviewCapability[]> {
  const { data, error } = await supabase.rpc('get_my_review_capabilities');

  if (error) {
    throw error;
  }

  return parseReviewCapabilities(data ?? []);
}

export async function loadReviewQueue(): Promise<ReviewQueueItem[]> {
  const { data, error } = await supabase.rpc('list_my_review_queue');

  if (error) {
    throw error;
  }

  return parseReviewQueue(data ?? []);
}

export async function loadReviewCase(
  caseType: string,
  caseId: string,
): Promise<ReviewCaseDetail> {
  const { data, error } = await supabase.rpc('get_my_review_case', {
    p_case_type: caseType,
    p_case_id: caseId,
  });

  if (error) {
    throw error;
  }

  return parseReviewCase(data);
}
