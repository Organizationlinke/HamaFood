import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return new Response(JSON.stringify({ error: 'Missing authorization' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

    const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: { user: caller } } = await callerClient.auth.getUser();
    if (!caller) throw new Error('Not authenticated');

    const { data: callerProfile } = await callerClient.from('profiles').select('role').eq('id', caller.id).single();
    if (callerProfile?.role !== 'gm') throw new Error('Only the General Manager can reset passwords');

    const body = await req.json();
    const userId = String(body.user_id ?? '');
    const newPassword = String(body.new_password ?? '');
    if (!userId || newPassword.length < 6) throw new Error('Invalid user or password');

    const admin = createClient(supabaseUrl, serviceKey);
    const { error } = await admin.auth.admin.updateUserById(userId, { password: newPassword });
    if (error) throw error;

    return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
