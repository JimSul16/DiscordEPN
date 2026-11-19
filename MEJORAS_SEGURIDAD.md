# Registro Integral de Mejoras de Seguridad y Correcciones de Arquitectura - Discord EPN

Este documento consolida y detalla todas las acciones, correcciones técnicas, hardening de seguridad y resolución de bugs implementados en el proyecto **Discord EPN** a lo largo del proceso de auditoría y remediación técnica en la rama `fix/security-audit`.

---

## 1. Resumen Ejecutivo y Estado de Commits

La auditoría inicial identificó vulnerabilidades severas de seguridad (como la exposición del archivo `.env` en los assets empaquetados para la web, falta de autenticación entre Firebase y Supabase con RLS deshabilitado o inoperante, permisos permisivos a usuarios anónimos en base de datos y almacenamiento, e inconsistencias en la captura y validación de archivos multimedia y tokens push), además de múltiples bugs funcionales y de concurrencia en la interfaz de chat.

Las remediaciones se consolidaron en dos fases reflejadas en el historial de Git:

1. **Commit `095688b` - Remediación base de seguridad, RLS, Auth Bridge y bugs funcionales:**
   - Desvinculación de `.env` del bundle de producción y migración a variables seguras en tiempo de compilación.
   - Creación del puente de autorización Firebase Auth → Supabase PostgREST / Realtime.
   - Implementación del script de migración SQL con 25 políticas de Row Level Security (RLS) y RPCs seguras.
   - Reglas de Firebase Storage y hardening en Android (`allowBackup=false`, `usesCleartextTraffic=false`).
   - Resolución de bugs de interfaz y concurrencia (BUG-01 al BUG-22).
2. **Commit `38c1003` - Remediación de bloqueantes, ciclo de vida FCM, formato de audio, validación estricta MIME y CSP:**
   - Corrección del ciclo de vida de FCM (orden de inicialización, registro post-login y listener `onTokenRefresh`).
   - Reingeniería del diálogo de grabación de voz (BUG-11) para escribir contenedores nativos `.m4a` (MP4) y `.wav` (RIFF), eliminando streams ADTS rotos.
   - Allowlists estrictas de tipos MIME y rechazo de extensiones desconocidas en subida de medios.
   - Envoltura transaccional atómica (`BEGIN ... COMMIT`) e índice único de reacciones en SQL.
   - Pruebas reales de impersonación de roles (`anon` vs `authenticated`) en SQL.
   - Configuración de Content-Security-Policy (CSP) en `firebase.json`.
   - Cobertura de pruebas unitarias ampliada a 15 tests pasando (`flutter test`) y código 100% limpio (`flutter analyze`).

---

## 2. Puente de Autenticación e Identidad (Firebase Auth ↔ Supabase Postgres)

### Diagnóstico Inicial
- Supabase operaba con el rol `anon` por defecto, ya que los usuarios se autenticaban únicamente en Firebase Auth.
- Activar RLS bajo esas condiciones bloqueaba por completo la aplicación porque las políticas evaluaban `auth.uid()`, el cual esperaba un UUID nativo de Supabase Auth en lugar de la cadena de 28 caracteres generada por Firebase Auth (`sub`).

### Soluciones Implementadas

1. **Inyección de Tokens JWT en Supabase Client:**
   - En `lib/core/services/supabase_service.dart`:
     - El cliente de Supabase se inicializa inyectando la función `accessToken` que obtiene el JWT actualizado de `FirebaseAuth.instance.currentUser?.getIdToken()`.
     - Se registra un listener a `FirebaseAuth.instance.idTokenChanges()` para sincronizar en tiempo real el token con el socket de Realtime mediante `_client.realtime.setAuth(token)`.
2. **Helper SQL para Firebase UID:**
   - En `sql/security_migration.sql`, se creó la función inmutable:
     ```sql
     create or replace function public.current_firebase_uid()
     returns text
     language sql
     stable
     as $$
       select coalesce(
         nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
         nullif(current_setting('request.jwt.claim.sub', true), ''),
         auth.jwt() ->> 'sub'
       );
     $$;
     ```
3. **Validación del Custom Claim `role: authenticated`:**
   - En `lib/core/config/app_config.dart`, se implementó `AppConfig.hasAuthenticatedRole(token)` para decodificar el payload JWT y verificar si el token emitido por Firebase incluye el claim `'role': 'authenticated'`.
   - En `lib/core/services/auth_service.dart`, tras el inicio de sesión y registro, se evalúa la presencia de este claim y se emite advertencia de depuración si falta.
   - En `lib/ui/home/home_screen.dart`, se despliega un banner superior interactivo informando al usuario si el token carece del claim, con un botón para refrescar la sesión una vez asignado por el backend.

---

## 3. Hardening de Base de Datos y Políticas de Seguridad RLS

### Script Transaccional: `sql/security_migration.sql`
Todo el script fue encapsulado dentro de un bloque de transacción atómica:
```sql
BEGIN;
  -- Definición de tablas, extensiones, índices, RLS y RPCs
COMMIT;
```

### Principales Medidas en Base de Datos:
1. **Revocación de Privilegios a `anon` y `public`:**
   - Se revocaron todos los permisos por defecto a `anon` y `public` sobre `profiles`, `rooms`, `room_members`, `messages`, `message_reactions`, `message_reads` y `push_tokens`.
   - Se otorgaron únicamente los permisos explícitos de `SELECT`, `INSERT`, `UPDATE` y `DELETE` al rol `authenticated`.
2. **25 Políticas RLS Estrictas:**
   - **`profiles`:** Los usuarios autenticados pueden ver perfiles; cada usuario solo puede editar su propio perfil (`id = public.current_firebase_uid()`).
   - **`rooms`:** Los usuarios solo pueden ver y acceder a salas públicas o privadas de las cuales son miembros comprobados en `room_members`. La creación exige que el creador sea el usuario actual.
   - **`room_members`:** Solo los miembros de una sala pueden ver la lista de integrantes; la auto-inscripción o expulsión está regulada por pertenencia y rol.
   - **`messages`:** Los usuarios solo pueden leer y enviar mensajes a las salas de las que son miembros activos. Solo el autor puede editar o eliminar su mensaje.
   - **`message_reactions`:** Lectura restringida a miembros de la sala del mensaje; inserción y eliminación limitada al autor de la reacción.
   - **`message_reads`:** Registro de confirmación de lectura restringido al usuario correspondiente.
   - **`push_tokens`:** Cada usuario solo puede insertar, actualizar o eliminar sus propios tokens de dispositivo.
3. **Índice Único Idempotente para Reacciones:**
   - Se estableció la restricción única:
     ```sql
     alter table public.message_reactions
       add constraint message_reactions_msg_usr_react_uidx
       unique (message_id, user_id, reaction);
     ```
   - Esto garantiza que la función RPC `toggle_reaction()` que ejecuta `insert ... on conflict do nothing` sea 100% idempotente y no genere inconsistencias o duplicados bajo alta concurrencia.
4. **Funciones RPC Seguras (`SECURITY DEFINER`):**
   - `toggle_reaction(p_message_id, p_reaction)`: Realiza la alternancia segura verificando pertenencia a la sala.
   - `mark_messages_as_read(p_room_id, p_last_message_id)`: Marca mensajes como leídos de forma masiva y segura.
5. **Pruebas Reales de Impersonación (`sql/verify_rls.sql`):**
   - Se añadieron verificaciones ejecutando `SET ROLE anon;` para comprobar que las consultas sean rechazadas con 0 filas o permiso denegado, y `SET ROLE authenticated;` simulando reclamos JWT para confirmar el acceso a datos legítimos.

---

## 4. Hardening de Almacenamiento y Validación de Medios (Storage)

### Validación Estricta en Cliente: `lib/core/services/storage_service.dart`
- **Allowlist Estricta de Tipos MIME:**
  - Imágenes permitidas: `image/jpeg`, `image/png`, `image/webp`, `image/gif`.
  - Audios permitidos: `audio/mp4`, `audio/m4a`, `audio/aac`, `audio/wav`, `audio/x-wav`, `audio/mpeg`, `audio/webm`, `audio/ogg`.
- **Límites de Tamaño:**
  - Avatares: Máximo 5 MB.
  - Multimedia de Chat: Máximo 10 MB.
  - Notas de Voz: Máximo 10 MB.
- **Sanitización de Nombres de Archivo:**
  - Se eliminan secuencias de escape de directorio (`../`, `..\\`), caracteres de control y espacios, reemplazándolos por prefijos temporales y caracteres seguros.
- **Corrección en `ChatInputBar`:**
  - Se eliminó el fallback inseguro que asignaba `image/jpeg` a cualquier archivo no reconocido; ahora arroja un error controlado con retroalimentación inmediata al usuario.

### Reglas de Firebase Storage: `storage.rules`
- Se configuraron reglas de Firebase Storage que validan:
  - Autenticación activa (`request.auth != null`).
  - Tamaño de archivo (`request.resource.size <= 5 * 1024 * 1024` para avatares y `10 * 1024 * 1024` para chat).
  - Coincidencia de tipo MIME con la extensión solicitada.

---

## 5. Corrección de Bugs Críticos de Interfaz y Concurrencia

| Bug ID | Descripción del Problema | Solución Técnica Implementada |
|---|---|---|
| **BUG-01** | **Historial y paginación rota:** Al cargar mensajes anteriores, el orden se invertía o duplicaba. | En `supabase_service.dart`, la consulta histórica se ordena por `created_at desc` con cursor `< cursorMessage.createdAt`, y en cliente se invierte la lista antes de concatenarla al inicio del buffer. |
| **BUG-02** | **Condición de carrera al cambiar de canal:** Clics rápidos entre canales mezclaban mensajes de salas distintas. | Se implementó el token cancelable `_roomRequest` en `chat_provider.dart`. Cada petición invalida las anteriores; si la respuesta que llega no coincide con el token activo, se descarta silenciosamente. |
| **BUG-03** | **Auto-scroll molesto:** Nuevos mensajes desplazaban la pantalla aunque el usuario estuviera leyendo el historial superior. | En `home_screen.dart`, se monitoriza `_wasNearBottom` (umbral de 120 px). El scroll automático hacia abajo solo ocurre si el usuario ya estaba al final o en la carga inicial de la sala. |
| **BUG-04** | **Drawer lateral no cerraba en móvil:** Al seleccionar un canal en pantallas pequeñas, la barra lateral quedaba abierta sobre el chat. | Se agregó `Scaffold.maybeOf(context)?.closeDrawer()` al invocar `selectRoom()` en `channel_sidebar.dart`. |
| **BUG-07** | **Reconstrucciones infinitas en AuthGate:** La navegación oscilaba entre Login y Home. | `AuthGate` en `lib/main.dart` se refactorizó como un `StatefulWidget` que retiene el ID de inicialización (`_initializedFor`), evitando llamadas cíclicas a `initializeUserData()`. |
| **BUG-09** | **Saturación por eventos de "escribiendo...":** Cada pulsación enviaba un evento por socket sin límite. | En `chat_input_bar.dart`, se implementó debounce con bandera `_typingSent` y un temporizador de refresco cada 4 segundos. |
| **BUG-11** | **Notas de voz corruptas:** La grabación generaba paquetes ADTS crudos sin contenedor MP4 o PCM sin cabecera WAV. | Se rediseñó `voice_record_dialog.dart`: en móvil/desktop se graba a archivo temporal con `AudioEncoder.aacLc` generando un contenedor `.m4a` con átomos `moov`/`mdat` nativos. En Web se graba con `AudioEncoder.wav` con cabecera estándar RIFF. Se incorporó límite estricto de 60 segundos. |
| **BUG-13** | **Overflow en edición de perfil:** El teclado virtual provocaba RenderFlex overflow y la imagen se subía antes de guardar. | En `profile_dialog.dart`, se envolvió la vista en `SingleChildScrollView`, se añadió validación de nombre (3-32 caracteres) y la subida de la imagen seleccionada se difirió hasta presionar "Guardar". |
| **BUG-14** | **Reproducción de audio solapada y fugas de memoria:** Múltiples audios sonaban a la vez y los listeners quedaban vivos. | `ChatProvider` coordina la variable `activeAudioMessageId`. En `message_bubble.dart`, cada burbuja detiene su reproducción si otra inicia, y en `dispose()` se cancelan explícitamente los 3 stream subscriptions del reproductor. |
| **BUG-16** | **Filtros de canal incompletos en Realtime:** Las reacciones y lecturas no filtraban por sala. | Se aplicó el filtro `PostgresChangeFilterType.eq` por `room_id` en las tres suscripciones (`messages`, `message_reactions`, `message_reads`) en `supabase_service.dart`. |
| **BUG-22** | **Pérdida de texto si fallaba el envío:** El input se limpiaba inmediatamente al presionar enviar. | En `chat_input_bar.dart`, la limpieza del campo de texto `_controller.clear()` se movió para ejecutarse únicamente tras la confirmación exitosa del `await`. Si ocurre un error, el texto se preserva. |

---

## 6. Ciclo de Vida y Persistencia de Tokens Push (FCM)

### Problema Identificado en la Auditoría
En la implementación inicial, `upsertPushToken` se ejecutaba en `main.dart` antes de llamar a `SupabaseService.initialize()`, lo que generaba una excepción silenciada en el bloque `catch (_) {}`. Adicionalmente, el token no se registraba cuando un nuevo usuario iniciaba sesión ni se actualizaba ante rotaciones.

### Solución Implementada
1. **Orden de Ejecución en `lib/main.dart`:**
   - Se garantizó que `await SupabaseService.initialize()` se complete exitosamente antes de solicitar el token FCM.
   - El registro inicial se ejecuta con manejo de errores visible en consola mediante `debugPrint`.
2. **Listener de Rotación de Tokens:**
   - En `lib/main.dart`, se añadió la escucha reactiva:
     ```dart
     FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
       SupabaseService.upsertPushToken(newToken);
     });
     ```
3. **Sincronización en Inicio de Sesión y Registro:**
   - En `lib/core/services/auth_service.dart`, tanto en `register()` como en `login()`, se invoca inmediatamente `await syncFcmToken()`, asegurando que el token de Firebase Messaging quede vinculado al UID del usuario activo en la tabla `push_tokens` de Supabase.

---

## 7. Hardening Web y Móvil

1. **Content-Security-Policy (CSP) en `firebase.json`:**
   Se incorporó la cabecera CSP para mitigar ataques XSS y Clickjacking en la versión Web:
   ```json
   {
     "key": "Content-Security-Policy",
     "value": "default-src 'self'; script-src 'self' 'unsafe-inline' https://www.gstatic.com https://apis.google.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self' data: blob: https:; media-src 'self' blob: https:; connect-src 'self' https://*.supabase.co wss://*.supabase.co https://*.googleapis.com https://identitytoolkit.googleapis.com https://securetoken.googleapis.com; frame-src 'self' https://*.firebaseapp.com;"
   }
   ```
2. **Protección de Secretos:**
   - Se removió `.env` de los assets empaquetados en `pubspec.yaml`.
   - Se añadieron `.env`, `key.properties`, `config/dev.json` y `google-services.json` a `.gitignore`.
3. **Hardening de Android (`AndroidManifest.xml`):**
   - `android:allowBackup="false"` y reglas estrictas de exclusión en `data_extraction_rules.xml` y `backup_rules.xml`.
   - `android:usesCleartextTraffic="false"` para forzar HTTPS en toda la comunicación.
   - `android/app/build.gradle.kts` configurado para compilar builds de release firmados mediante `key.properties`.

---

## 8. Verificación y Pruebas Automatizadas

Se añadieron y ejecutaron suites de pruebas automatizadas:
- **`flutter analyze`:** **0 advertencias / 0 errores** encontrados en todo el proyecto.
- **`flutter test`:** **15/15 pruebas unitarias pasando** exitosamente en `test/models_and_constants_test.dart` y `test/widget_test.dart`, cubriendo:
  - Constantes de interfaz y paleta de colores oficial de Discord.
  - Modelos de dominio (`UserProfile`, `RoomModel`, `MessageModel`, `ReactionModel`).
  - Detección y parseo del claim JWT `role: authenticated` en `AppConfig`.
  - Exclusiones mutuas de audio y bandera de autorización en `ChatProvider`.
  - Validación de extensiones, tamaños y allowlist MIME estricta en `StorageService`.

---

## 9. Pasos Restantes para Despliegue en Producción (Consolas Externas)

1. **Supabase Dashboard (SQL Editor):**
   - Ejecutar el script [sql/security_migration.sql](sql/security_migration.sql).
   - Ejecutar el script de verificación [sql/verify_rls.sql](sql/verify_rls.sql).
2. **Supabase Auth (Third-Party Provider):**
   - En *Authentication > Providers > Third-Party Auth*, habilitar el proveedor de Firebase con el Project ID de tu proyecto.
3. **Firebase Cloud Functions (Custom Claim Obligatorio):**
   - Desplegar una Cloud Function (o Auth Blocking Function) para inyectar automáticamente el claim `{ role: 'authenticated' }` al crearse cada usuario en Firebase Auth.
4. **Firebase Deploy:**
   - Ejecutar `firebase deploy --only hosting,storage` para publicar las reglas de almacenamiento y las cabeceras CSP.
5. **Generación de Keystore Android:**
   - Crear el archivo `android/key.properties` con la ruta y contraseñas de la llave de firma privada para generar el bundle de producción (`flutter build appbundle --release`).

### Lo que Falta (Acciones Fuera del Código / Consolas)

  Para completar el despliegue al 100%, solo restan los pasos
  administrativos en las consolas de servicios externos:

  1. Supabase SQL Editor:
      • Ejecutar security_migration.sql (ahora envuelto en BEGIN ...
      COMMIT).
      • Ejecutar verify_rls.sql para comprobar las políticas con SET ROLE
      anon y SET ROLE authenticated.
  2. Supabase Auth Configuration:
      • En Authentication > Providers > Third-Party Auth, activar el
      proveedor de Firebase con tu Project ID.
  3. Firebase Auth Custom Claims:
      • Desplegar el trigger en Firebase Functions para asignar { role:
      'authenticated' } a los usuarios registrados.
  4. Firebase Deploy:
      • Ejecutar firebase deploy --only hosting,storage para aplicar las
      storage.rules y las cabeceras CSP de firebase.json.
  5. Generar Keystore de Producción (Android):
      • Crear el archivo android/key.properties con las credenciales de
      tu keystore para firmar el bundle de release.
