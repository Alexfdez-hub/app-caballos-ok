import { NativeModules, Platform } from 'react-native';

const configuredUrl = process.env.EXPO_PUBLIC_SUPABASE_URL?.trim();
const supabaseAnonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY?.trim().replace(
  /^<|>$/g,
  '',
);

if (!configuredUrl || !supabaseAnonKey) {
  throw new Error(
    'Missing Supabase configuration. Set EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY.',
  );
}

try {
  if (new URL(configuredUrl).hostname === 'your-project.supabase.co') {
    throw new Error(
      'EXPO_PUBLIC_SUPABASE_URL is still the example host your-project.supabase.co. Put the real project URL in .env.supabase.remote and run npm run start:remote.',
    );
  }
} catch (error) {
  if (!(error instanceof TypeError)) {
    throw error;
  }
}

function looksLikeSupabaseAnonKey(value: string) {
  return value.startsWith('eyJ') || value.startsWith('sb_publishable_');
}

function getPackagerHost() {
  const scriptURL = NativeModules.SourceCode?.scriptURL as string | undefined;
  const host = scriptURL?.match(/^https?:\/\/([^/:]+)/)?.[1];

  if (!host || host === '127.0.0.1' || host === 'localhost') {
    return null;
  }

  return host;
}

function resolveSupabaseUrl(url: string) {
  if (Platform.OS === 'web') {
    return url;
  }

  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return url;
  }

  if (parsed.hostname !== '127.0.0.1' && parsed.hostname !== 'localhost') {
    return url;
  }

  const packagerHost = getPackagerHost();
  if (!packagerHost) {
    return url;
  }

  parsed.hostname = packagerHost;
  return parsed.toString();
}

const supabaseUrl = resolveSupabaseUrl(configuredUrl);

try {
  console.info('[auth] supabase host', new URL(supabaseUrl).host);
} catch {
  console.warn('[auth] EXPO_PUBLIC_SUPABASE_URL is not a valid URL');
}

if (!looksLikeSupabaseAnonKey(supabaseAnonKey)) {
  console.warn(
    '[auth] EXPO_PUBLIC_SUPABASE_ANON_KEY does not look like a Supabase anon JWT or publishable key.',
  );
}

export const env = {
  supabaseUrl,
  supabaseAnonKey,
} as const;
