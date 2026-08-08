import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors={
  'Access-Control-Allow-Origin':Deno.env.get('APP_ORIGIN')??'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS',
};
const headers={...cors,'Content-Type':'application/json'};
const enc=new TextEncoder();
async function sha256(v:string){const b=await crypto.subtle.digest('SHA-256',enc.encode(v));return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('');}
function response(body:Record<string,unknown>,status=200){return new Response(JSON.stringify(body),{status,headers});}

Deno.serve(async(req)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
  if(req.method!=='POST')return response({error:'Method not allowed'},405);
  try{
    const url=Deno.env.get('SUPABASE_URL'); const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'); const pepper=Deno.env.get('OTP_PEPPER');
    if(!url||!service||!pepper)throw new Error('server_configuration');
    const s=createClient(url,service);
    const {email,code}=await req.json();
    const normalized=String(email??'').trim().toLowerCase(); const otp=String(code??'');
    if(!/^\d{6}$/.test(otp))return response({error:'Código inválido o vencido'},400);

    const ip=(req.headers.get('x-forwarded-for')??req.headers.get('cf-connecting-ip')??'unknown').split(',')[0].trim();
    const subject=await sha256(`verify:${ip}:${normalized}:${pepper}`);
    const {data:allowed}=await s.rpc('consume_verification_rate_limit',{p_scope:'otp_verify_15m',p_subject_hash:subject,p_window_seconds:900,p_max_requests:15});
    if(allowed!==true)return response({error:'Demasiados intentos. Intenta más tarde.'},429);

    const {data:userId,error:lookupError}=await s.rpc('internal_user_id_by_email',{p_email:normalized});
    if(lookupError)throw lookupError;
    if(!userId)return response({error:'Código inválido o vencido'},400);

    const {data:row}=await s.from('verification_codes').select('*').eq('user_id',userId).is('used_at',null).order('created_at',{ascending:false}).limit(1).maybeSingle();
    if(!row||new Date(row.expires_at).getTime()<Date.now()||(row.blocked_until&&new Date(row.blocked_until).getTime()>Date.now()))return response({error:'Código inválido o vencido'},400);

    const hash=await sha256(`${otp}:${pepper}`);
    if(hash!==row.code_hash){
      const attempts=row.attempts+1;
      await s.from('verification_codes').update({attempts,blocked_until:attempts>=5?new Date(Date.now()+15*60000).toISOString():null}).eq('id',row.id);
      return response({error:'Código inválido o vencido'},400);
    }

    await s.from('verification_codes').update({used_at:new Date().toISOString()}).eq('id',row.id);
    await s.from('profiles').update({email_verified:true,updated_at:new Date().toISOString()}).eq('id',userId);
    const owner=(Deno.env.get('OWNER_EMAIL')??'').trim().toLowerCase();
    if(owner&&normalized===owner){
      const {error:ownerError}=await s.rpc('assign_owner',{p_user_id:userId});
      if(ownerError)throw ownerError;
    }
    await s.from('audit_logs').insert({actor_id:userId,action:'email_verified',target_user_id:userId});
    return response({ok:true});
  }catch(_){
    console.error('verification failed');
    return response({error:'No se pudo verificar.'},500);
  }
});
