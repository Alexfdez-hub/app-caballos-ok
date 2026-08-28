import { createClient } from '@supabase/supabase-js';
import AsyncStorage from '@react-native-async-storage/async-storage';

const SUPABASE_URL = 'https://efkauegdlmfkonzwyyiv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVma2F1ZWdkbG1ma29uend5eWl2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc4MTU0ODcsImV4cCI6MjEwMzM5MTQ4N30.z0lgJrNfVHEGWAfLIlwjKNVCVOKma-3Q597Q3-e-_WM';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    storage: AsyncStorage,
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: false,
  },
});