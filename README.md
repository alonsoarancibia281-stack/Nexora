# Nexora Markets AI

Aplicación móvil profesional de análisis educativo y probabilístico de mercados de criptomonedas.

> Nexora Markets AI no custodia fondos, no ejecuta operaciones y no garantiza resultados financieros.

## Predicción BTC

La pantalla de predicción trabaja tres rondas a la vez: **5 minutos, 15 minutos y 1 hora**. Cada ronda abre y cierra en una hora exacta de reloj, igual que la vela de Binance que la liquida (`:00`, `:05`, `:15`, en punto…). El contador se sincroniza con el reloj del servidor de Binance y, al cerrar una ronda, vuelve a sincronizar, abre la siguiente y refresca los datos sin tocar nada.

Deciden seis agentes, no cien: **Tendencia, Impulso, Flujo, Liquidez, Volatilidad y Reversión**. Cada uno mira una sola cosa, lleva sus propias reglas de mercado (por ejemplo: el flujo miente con el spread abierto; no se pelea contra un impulso con volumen) y pesa distinto según la ronda: liquidez y flujo mandan en 5 minutos, tendencia y contexto mandan en 1 hora. Los agentes se puntúan solos con cada cierre y el que acierta pesa más en la siguiente ronda.

- **Avisos**: cuando abre una señal, cuando el equipo cambia de lado y cuando toca salir.
- **Salida anticipada**: la vigilancia mide cuánta ventaja queda frente al mejor momento de la ronda, si el precio se fue en contra y cuánto tiempo falta, y avisa *antes* del cierre.
- **Honestidad**: la probabilidad nunca pasa del 90% (85% en 1 hora). Ninguna ronda está garantizada.

## Interfaz

Tema claro y oscuro con ajuste propio, barra lateral responsive que se expande al pasar el ratón, barra inferior de pastillas en móvil, jerarquía de botones (`NexoraButton`) con texto siempre en una línea y un fondo de shader gradient animado detrás de toda la app.

## Fase 1

La rama de Fase 1 implementa la base de identidad y seguridad: Flutter + Riverpod + GoRouter, Supabase Auth/PostgreSQL, registro, verificación OTP de seis dígitos, recuperación de contraseña, consentimientos, roles, planes, entitlements, sesiones/dispositivos y acceso Owner validado exclusivamente en servidor.

También incluye un panel administrativo base para Owner con métricas, búsqueda de usuarios, cambio de plan, suspensión/reactivación, feature flags y auditoría. El Owner está protegido contra degradación o suspensión por las operaciones administrativas normales.

La verificación de correo usa OTP generado criptográficamente en Edge Functions, hash + pepper, expiración, un solo uso, bloqueo por intentos, rate limiting por correo/IP, respuestas anti-enumeración y lookup interno restringido a `service_role`.

## Configuración Flutter

Usa variables de compilación públicas, no archivos `.env` empaquetados:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY \
  --dart-define=PASSWORD_RECOVERY_REDIRECT=nexora://update-password
```

Los secretos (`OWNER_EMAIL`, `OTP_PEPPER`, `RESEND_API_KEY`, `EMAIL_FROM`, `APP_ORIGIN`) deben configurarse únicamente en Supabase/Edge Functions.

Consulta `docs/PHASE_1.md` y `docs/PHASE_1_CHECKLIST.md` para instalación, seguridad y pendientes de staging.
