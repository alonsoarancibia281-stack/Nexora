# Nexora Markets AI — Supabase Staging

## 1. Crear el proyecto

Crea un proyecto nuevo en el dashboard de Supabase con nombre recomendado `nexora-staging`. Guarda de forma segura la contraseña de Postgres.

Después abre **Connect** y copia:
- Project URL
- Publishable key
- Project ref

La app Flutter usa únicamente Project URL + Publishable key. Nunca coloques service role keys en Flutter.

## 2. Preparar secretos

Copia localmente:

```bash
cp supabase/.env.staging.example supabase/.env.staging
```

Rellena el archivo local con:
- `OWNER_EMAIL`: correo propietario configurado por el responsable del proyecto.
- `OTP_PEPPER`: secreto largo y aleatorio.
- `RESEND_API_KEY`: API key del proveedor de correo.
- `EMAIL_FROM`: remitente validado.
- `APP_BASE_URL`: URL web de staging, si existe.
- `APP_ORIGIN`: origen permitido para llamadas web administrativas.

Nunca hagas commit de `supabase/.env.staging`.

## 3. Desplegar

Desde la raíz del repositorio:

```bash
export SUPABASE_PROJECT_REF="tu-project-ref"
export SUPABASE_DB_PASSWORD="tu-password-db"
bash scripts/deploy_staging.sh
```

El script:
1. enlaza el proyecto;
2. hace dry-run de migraciones;
3. aplica migraciones;
4. carga secretos;
5. despliega las tres Edge Functions.

## 4. Configurar Flutter

Ejecuta la app con configuración pública compile-time:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://TU_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=TU_PUBLISHABLE_KEY \
  --dart-define=PASSWORD_RECOVERY_REDIRECT=nexora://update-password
```

## 5. Configurar Resend

Valida un dominio remitente en Resend y configura `EMAIL_FROM`. El OTP debe llegar como texto HTML real, no como imagen.

## 6. Verificaciones de staging

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

## 7. No hacer todavía

No uses staging como producción, no publiques service-role keys, no habilites pagos reales y no mezcles datos reales de clientes hasta completar revisión de seguridad, políticas legales y pruebas end-to-end.
