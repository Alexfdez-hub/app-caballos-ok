import { supabase } from '../../services/supabase/client';
import { parseMyEquineDetail, parseMyEquineSummary } from './equineCreate';
import type { MyEquineDetail, MyEquineSummary } from './equineCreate';

export type CreateMyEquineInput = {
  name: string;
  equineType: 'HORSE' | 'PONY';
};

export async function createMyEquine(input: CreateMyEquineInput): Promise<string> {
  const { data, error } = await supabase.rpc('create_my_equine', {
    p_name: input.name,
    p_equine_type: input.equineType,
  });

  if (error) {
    throw error;
  }

  if (typeof data !== 'string' || data.length === 0) {
    throw new Error('Equine RPC returned an unexpected result.');
  }

  return data;
}

export async function listMyEquines(): Promise<MyEquineSummary[]> {
  const { data, error } = await supabase.rpc('list_my_equines');

  if (error) {
    throw error;
  }

  return ((data ?? []) as unknown[]).map((row) => parseMyEquineSummary(row));
}

export async function getMyEquine(equineId: string): Promise<MyEquineDetail> {
  const { data, error } = await supabase.rpc('get_my_equine', {
    p_equine_id: equineId,
  });

  if (error) {
    throw error;
  }

  const row = Array.isArray(data) ? data[0] : data;
  return parseMyEquineDetail(row);
}
