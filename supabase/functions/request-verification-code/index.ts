import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { verificationHtml, verificationText } from '../_shared/email.ts';

const cors = {
  'Access-Control-Allow-Origin': Deno.env.get('APP_ORIGIN') ?? '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const jsonHeaders = {...cors, 'Content-Type':'application/json'};
const enc = new TextEncoder();
async function sha256(value:string){const b=await crypto.subtle.digest('SHA-256',enc.encode(value));return [...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('');}
function secureCode(){const a=new Uint32Array(1);crypto.getRandomValues(a);return String(a[0]%1000000).padStart(6,'0');}
function response(body:Record<string,unknown>,status=200){return new Response(JSON.stringify(body),{status,headers:jsonHeaders});}

Deno.serve(async(req)=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  if(req.method!=='POST') return response({error:'Method not allowed'},405);
  try{
    const url=Deno.env.get('SUPABASE_URL'); const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const pepper=Deno.env.get('OTP_PEPPER'); const key=Deno.env.get('RESEND_API_KEY'); const from=Deno.env.get('EMAIL_FROM');
    if(!url||!service||!pepper||!key||!from) throw new Error('server_configuration');
    const supabase=createClient(url,service);
    const {email}=await req.json(); const normalized=String(email??'').trim().toLowerCase();
    if(!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalized)) return response({ok:true});

    const ip=(req.headers.get('x-forwarded-for')??req.headers.get('cf-connecting-ip')??'unknown').split(',')[0].trim();
    const emailSubject=await sha256(`email:${normalized}:${pepper}`); const ipSubject=await sha256(`ip:${ip}:${pepper}`);
    const {data:emailAllowed}=await supabase.rpc('consume_verification_rate_limit',{p_scope:'otp_email_15m',p_subject_hash:emailSubject,p_window_seconds:900,p_max_requests:5});
    const {data:ipAllowed}=await supabase.rpc('consume_verification_rate_limit',{p_scope:'otp_ip_15m',p_subject_hash:ipSubject,p_window_seconds:900,p_max_requests:20});
    if(emailAllowed!==true||ipAllowed!==true) return response({error:'Demasiadas solicitudes. Intenta más tarde.'},429);

    const {data:userId,error:lookupError}=await supabase.rpc('internal_user_id_by_email',{p_email:normalized});
    if(lookupError) throw lookupError;
    if(!userId) return response({ok:true});

    const {data:last}=await supabase.from('verification_codes').select('created_at').eq('user_id',userId).order('created_at',{ascending:false}).limit(1).maybeSingle();
    if(last&&Date.now()-new Date(last.created_at).getTime()<60000) return response({error:'Espera 60 segundos antes de reenviar.'},429);

    await supabase.from('verification_codes').update({used_at:new Date().toISOString()}).eq('user_id',userId).is('used_at',null);
    const code=secureCode();
    const {error:insertError}=await supabase.from('verification_codes').insert({user_id:userId,code_hash:await sha256(`${code}:${pepper}`),expires_at:new Date(Date.now()+600000).toISOString()});
    if(insertError) throw insertError;

    const sent=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},body:JSON.stringify({from,to:[normalized],subject:'Verifica tu cuenta en Nexora Markets AI',html:verificationHtml(code),text:verificationText(code)})});
    if(!sent.ok) throw new Error('email_provider');
    return response({ok:true});
  }catch(_){
    console.error('verification request failed');
    return response({error:'No se pudo procesar la solicitud.'},500);
  }
});
