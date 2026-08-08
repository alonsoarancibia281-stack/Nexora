# Fase 1 — Nexora Markets AI

## Módulos implementados

- **Bootstrap Flutter:** inicia Riverpod, Supabase y el tema oscuro.
- **Autenticación:** registro e inicio de sesión con Supabase Auth; las contraseñas no se almacenan manualmente.
- **Recuperación:** flujo de recuperación con mensaje anti-enumeración.
- **Verificación:** OTP numérico de seis dígitos generado criptográficamente en Edge Function, hash SHA-256 + pepper, expiración de 10 minutos, un solo uso, reenvío a los 60 segundos y bloqueo temporal tras cinco fallos.
- **Reenvío desde login:** una cuenta no verificada puede solicitar otro código sin entrar a la aplicación.
- **Consentimiento:** registra versión de términos, privacidad, país y preferencia de marketing.
- **Autorización:** roles y planes persistidos en PostgreSQL con RLS. Los privilegios no dependen de botones ocultos en Flutter.
- **Entitlements:** matriz centralizada en backend para límites, IA, backtesting, reportes y acceso administrativo.
- **Owner:** la Edge Function compara el correo normalizado con `OWNER_EMAIL` y llama una función SQL no accesible al cliente. No existe condición especial en Flutter.
- **Protección Owner:** las operaciones normales no pueden degradar el rol ni reemplazar el plan Owner.
- **Sesiones:** pantalla de perfil y seguridad, listado de dispositivos, cierre de sesión actual y cierre global.
- **Correo:** HTML responsive y texto plano; el OTP es texto real y copiable.
- **Pruebas:** validadores, entitlements, contrato OTP y contratos SQL de seguridad.
- **CI:** GitHub Actions ejecuta `flutter analyze` y `flutter test` en PRs y ramas de trabajo.

## Configuración

1. Instala Flutter estable y ejecuta `flutter pub get`.
2. Crea un proyecto Supabase.
3. Ejecuta las migraciones de `supabase/migrations/` en orden.
4. Copia `.env.example` a `.env` y configura únicamente URL y anon key públicas.
5. En Supabase Secrets configura `OWNER_EMAIL`, `OTP_PEPPER`, `RESEND_API_KEY` y `EMAIL_FROM`.
6. Despliega `register-consent`, `request-verification-code` y `verify-email-code`.
7. Configura Resend y verifica el dominio remitente.
8. Ejecuta `flutter test`, `flutter analyze` y luego `flutter run`.
9. Ejecuta `supabase/tests/phase1_security.sql` contra staging para validar invariantes de seguridad.

## Seguridad

Nunca publiques `.env`, service role keys, `OTP_PEPPER` ni claves del proveedor de correo. `OWNER_EMAIL` es configuración exclusiva del servidor. La tabla `verification_codes` no tiene políticas de acceso para clientes. La función `assign_owner(uuid)` está revocada para `anon` y `authenticated`.

## Pendiente antes de producción

Configurar CAPTCHA/rate limiting perimetral, enlaces reales de términos/privacidad/soporte, Google Sign-In, FCM, identificación estable y segura del dispositivo, deep links de recuperación, despliegue de staging y pruebas de integración end-to-end con un proyecto Supabase real.
