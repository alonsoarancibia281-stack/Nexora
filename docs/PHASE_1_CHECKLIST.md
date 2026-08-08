# Checklist de cierre — Fase 1

## Aplicación
- [x] Bootstrap Flutter + Riverpod + GoRouter
- [x] Registro con validaciones
- [x] Términos y privacidad obligatorios
- [x] Inicio de sesión
- [x] Recuperación y actualización de contraseña
- [x] Verificación OTP de 6 dígitos
- [x] Reenvío OTP desde login
- [x] Guard central de rutas autenticadas
- [x] Perfil y seguridad
- [x] Registro estable de instalación/dispositivo
- [x] Cierre de sesión actual
- [x] Cierre global de sesiones
- [x] Pantalla de planes y límites
- [x] Panel administrativo base Owner
- [x] Búsqueda de usuarios
- [x] Cambio administrativo de plan
- [x] Suspensión/reactivación de cuentas
- [x] Gestión de feature flags

## Backend y seguridad
- [x] Supabase Auth
- [x] PostgreSQL + RLS
- [x] Roles y planes
- [x] Entitlements centralizados
- [x] Owner validado únicamente en servidor
- [x] Protección contra degradación/suspensión del Owner
- [x] Consentimiento auditable
- [x] OTP hasheado con pepper
- [x] Expiración, reenvío y bloqueo por intentos
- [x] Rate limiting por correo e IP para OTP
- [x] Lookup de identidad por correo restringido a service role
- [x] Respuestas anti-enumeración
- [x] CORS configurable para Edge Functions
- [x] Auditoría de cambios administrativos
- [x] Tests SQL de invariantes y permisos administrativos
- [x] CI Flutter (`analyze` + `test`)

## Requiere infraestructura externa
- [ ] Crear/configurar proyecto Supabase de staging
- [ ] Configurar `OWNER_EMAIL`
- [ ] Configurar `OTP_PEPPER`
- [ ] Configurar `APP_ORIGIN`
- [ ] Configurar Resend y dominio remitente
- [ ] Configurar deep links nativos de recuperación
- [ ] Ejecutar migraciones en staging
- [ ] Desplegar Edge Functions
- [ ] Ejecutar pruebas end-to-end reales
- [ ] Configurar FCM
- [ ] Configurar Google Sign-In cuando se habilite

La Fase 1 de código queda funcionalmente estructurada. Los elementos pendientes requieren credenciales, dominios y servicios externos y no deben almacenarse en el repositorio.
