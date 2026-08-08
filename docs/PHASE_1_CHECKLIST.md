# Checklist de cierre — Fase 1

## Aplicación
- [x] Bootstrap Flutter + Riverpod + GoRouter
- [x] Registro con validaciones
- [x] Términos y privacidad obligatorios
- [x] Inicio de sesión
- [x] Recuperación de contraseña
- [x] Verificación OTP de 6 dígitos
- [x] Reenvío OTP desde login
- [x] Perfil y seguridad
- [x] Cierre de sesión actual
- [x] Cierre global de sesiones

## Backend y seguridad
- [x] Supabase Auth
- [x] PostgreSQL + RLS
- [x] Roles y planes
- [x] Entitlements centralizados
- [x] Owner validado en servidor
- [x] Protección contra degradación del Owner
- [x] Consentimiento auditable
- [x] OTP hasheado con pepper
- [x] Expiración, reenvío y bloqueo por intentos
- [x] Tests SQL de invariantes
- [x] CI Flutter

## Requiere infraestructura externa
- [ ] Crear/configurar proyecto Supabase de staging
- [ ] Configurar `OWNER_EMAIL`
- [ ] Configurar `OTP_PEPPER`
- [ ] Configurar Resend y dominio remitente
- [ ] Configurar deep links de recuperación
- [ ] Ejecutar migraciones en staging
- [ ] Desplegar Edge Functions
- [ ] Ejecutar pruebas end-to-end reales
- [ ] Configurar FCM
- [ ] Configurar Google Sign-In cuando se habilite

La Fase 1 de código queda funcionalmente estructurada; los elementos pendientes dependen de credenciales, dominios y servicios externos que no deben almacenarse en el repositorio.
