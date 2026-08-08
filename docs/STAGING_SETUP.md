# Nexora Markets AI — Supabase Staging

## Estado actual

Proyecto Supabase activo:
- Project ref: `jyifsslfjyryoypwmxmq`
- Project URL: `https://jyifsslfjyryoypwmxmq.supabase.co`
- Migraciones de Fase 1: aplicadas
- Edge Functions: `register-consent`, `request-verification-code` y `verify-email-code` desplegadas y activas
- Security Advisor: acceso anónimo a funciones `SECURITY DEFINER` endurecido
- Performance Advisor: índices y políticas RLS optimizados

La app Flutter usa únicamente Project URL + Publishable key. Nunca coloques service role keys en Flutter.

## Configuración manual pendiente en Supabase

### 1. Auth > Providers > Email

Desactiva **Confirm email** para Nexora Staging. Nexora utiliza su propio flujo de verificación por código de 6 dígitos. El cliente cierra la sesión provisional inmediatamente después del registro y no permite login hasta que `profiles.email_verified` sea verdadero.

### 2. Edge Function secrets

Configura en Supabase los siguientes secretos:
- `OWNER_EMAIL`: correo propietario configurado por el responsable del proyecto.
- `OTP_PEPPER`: secreto largo, aleatorio y de alta entropía.
- `RESEND_API_KEY`: API key de Resend.
- `EMAIL_FROM`: remitente validado en Resend.
- `APP_ORIGIN`: origen web permitido cuando exista panel web.
- `APP_BASE_URL`: URL web de staging cuando exista.

`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` son proporcionados automáticamente por el entorno de Edge Functions de Supabase.

Nunca guardes los secretos anteriores en Flutter ni los publiques en GitHub.

## Configurar Flutter

Ejecuta la app con configuración pública compile-time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://jyifsslfjyryoypwmxmq.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=TU_PUBLISHABLE_KEY \
  --dart-define=PASSWORD_RECOVERY_REDIRECT=nexora://update-password
```

## Configurar Resend

Valida un dominio remitente en Resend y configura `EMAIL_FROM`. El OTP debe llegar como texto HTML real, no como imagen.

## Verificaciones de staging

Prueba en este orden:
1. registro de usuario Free;
2. rechazo de contraseña débil;
3. bloqueo si no acepta términos/privacidad;
4. recepción de OTP;
5. expiración a los 10 minutos;
6. reenvío bloqueado durante 60 segundos;
7. bloqueo tras 5 códigos incorrectos;
8. login rechazado antes de verificar;
9. login exitoso después de verificar;
10. recuperación de contraseña;
11. lectura de plan/entitlements;
12. cuenta Owner obtiene plan/rol Owner únicamente desde backend;
13. usuario normal no puede ejecutar RPC administrativas;
14. Owner puede abrir panel, gestionar usuarios y feature flags;
15. Owner no puede ser suspendido/degradado por operaciones administrativas normales.

## No hacer todavía

No uses staging como producción, no publiques service-role keys, no habilites pagos reales y no mezcles datos reales de clientes hasta completar revisión de seguridad, políticas legales y pruebas end-to-end.
