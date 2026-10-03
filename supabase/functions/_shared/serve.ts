import { createClient } from '@supabase/supabase-js';

import { adaptServerClient, handleEquinePhoto, userClientOptions, serverClientOptions } from './equinePhoto.ts';
import type { ServerPhotoClient, UserPhotoClient } from './equinePhoto.ts';

type PhotoAction = 'prepare' | 'finalize' | 'read' | 'retire';

export function serveEquinePhoto(action: PhotoAction) {
  Deno.serve(async (request) => {
    const url = Deno.env.get('SUPABASE_URL') ?? '';
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    if (!url || !anonKey || !serviceRoleKey || anonKey === serviceRoleKey) {
      return Response.json({ error: 'retry' }, { status: 503 });
    }

    const response = await handleEquinePhoto(action, request, {
      createUserClient(jwt) {
        const client = createClient(url, anonKey, userClientOptions(jwt));
        return {
          async rpc(name, args) {
            const { data, error } = await client.rpc(name, args);
            return {
              data,
              errorMessage: error?.message ?? null,
            };
          },
          async authenticatedUserId() {
            const { data, error } = await client.auth.getUser(jwt);
            if (error || !data.user?.id) {
              return null;
            }
            return data.user.id;
          },
        } satisfies UserPhotoClient;
      },
      createServerClient() {
        const client = createClient(url, serviceRoleKey, serverClientOptions());
        const storage = adaptServerClient(client.storage.from('equine-media'));
        return {
          ...storage,
          async mutateMetadata(name, mediaId, authUserId) {
            const { data, error } = await client.rpc(name, {
              p_media_id: mediaId,
              p_auth_user_id: authUserId,
            });
            return {
              data,
              errorMessage: error?.message ?? null,
            };
          },
        } satisfies ServerPhotoClient;
      },
    });

    return Response.json(response.body, { status: response.status });
  });
}
