# Fase 1 — Nexora Markets AI

## Módulos

- **Bootstrap Flutter:** inicia Riverpod, Supabase y el tema oscuro.
- **Autenticación:** registro e inicio de sesión con Supabase Auth; las contraseñas no se almacenan manualmente.
- **Verificación:** OTP numérico de seis dígitos generado criptográficamente en Edge Function, hash SHA-256 + pepper, expiración de 10 minutos, un solo uso, reenvío a los 60 segundos y bloqueo temporal tras cinco fallos.
- **Consentimiento:** registra versión de términos, privacidad, país y preferencia de marketing.
- **Autorización:** roles y planes persistidos en PostgreSQL con RLS. Los privilegios no dependen de botones ocultos en Flutter.
- **Owner:** la Edge Function compara el correo normalizado con `OWNER_EMAIL` y llama una función SQL no accesible al cliente. No existe condición especial en Flutter.
- **Correo:** HTML responsive y texto plano; el OTP es texto real y copiable.

## Configuración

1. Instala Flutter estable y ejecuta `flutter pub get`.
2. Crea un proyecto Supabase.
3. Ejecuta `supabase/migrations/202608080001_phase1.sql`.
4. Copia `.env.example` a `.env` y configura únicamente URL y anon key públicas.
5. En Supabase Secrets configura `OWNER_EMAIL`, `OTP_PEPPER`, `RESEND_API_KEY` y `EMAIL_FROM`.
6. Despliega `register-consent`, `request-verification-code` y `verify-email-code`.
7. Configura Resend y verifica el dominio remitente.
8. Ejecuta `flutter test`, `flutter analyze` y luego `flutter run`.

## Seguridad

Nunca publiques `.env`, service role keys, `OTP_PEPPER` ni claves del proveedor de correo. `OWNER_EMAIL` es un secreto/configuración exclusiva del servidor. La tabla `verification_codes` no tiene políticas de acceso para clientes.

## Pendiente antes de producción

Configurar CAPTCHA/rate limiting perimetral, enlaces reales de términos/privacidad/soporte, Google Sign-In, FCM, cierre global de sesiones, instrumentación de dispositivos y pruebas de integración contra un proyecto Supabase de staging.
