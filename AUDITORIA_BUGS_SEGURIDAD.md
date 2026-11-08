# Auditoría de bugs y seguridad — Discord EPN

> **Destinatario:** Gemini (agente de implementación).
> **Objetivo:** aplicar las correcciones de este documento sin romper la aplicación.
> **Alcance auditado:** commit `c86e4df` (rama actual), `lib/`, `test/`, `pubspec.yaml`, configuración Android/Web, `.env`, `.gitignore`, documentación (`README.md`, `PLAN_PROYECTO_DISCORD_EPN.md`, `CHECKPOINT_PROYECTO.md`).
> **Fecha de auditoría:** 7 de noviembre de 2026.
> **Estado del código:** `flutter analyze` → 0 issues; `flutter test` → 7/7 pruebas pasan. Eso **no** significa que sea seguro: las pruebas actuales no cubren RLS, concurrencia, errores de red ni reglas de Storage.

---

## 0. Cómo debe trabajar Gemini (leer antes de tocar código)

1. **No aplicar todo de golpe.** Seguir el orden de la sección 7. Hay dependencias reales: activar RLS antes de conectar Firebase Auth con Supabase deja la app completamente vacía.
2. **Crear una rama** (`fix/security-audit`) y hacer commits pequeños por fase.
3. **No pegar claves reales** en código, tests, capturas ni en este documento. Usar `--dart-define` o un archivo local ignorado por git.
4. **Después de cada fase:** ejecutar `flutter analyze`, `flutter test`, y las verificaciones de la sección 12.
5. **No “arreglar” un síntoma silenciando la excepción.** Varias funciones actuales hacen `catch (_) {}` o `catch (_) { return []; }`; eso es parte del problema, no la solución.
6. **No cambiar el esquema a ciegas.** Antes de ejecutar SQL, revisar si hay datos que violan las nuevas restricciones (sección 8.1).
7. **Los UID de Firebase no son UUID.** Nunca usar `auth.uid()` para comparar con `profiles.id`; usar `auth.jwt() ->> 'sub'` (sección 8.2). Este es el error más probable al implementar RLS con Firebase.

---

## 1. Resumen ejecutivo

La app funciona en el “camino feliz”, pero la seguridad real del backend no está implementada:

- **RLS no está activo.** Se verificó empíricamente contra el proyecto real: el rol `anon` puede leer `rooms` y los `INSERT`/`UPDATE` llegan hasta las restricciones de la tabla (FK, NOT NULL) en vez de ser rechazados por permisos. Cualquiera con la publishable key (que es pública por diseño) puede leer y escribir datos.
- **Supabase nunca recibe la identidad del usuario.** `Supabase.initialize` no configura `accessToken` ni se llama a `realtime.setAuth`; todas las consultas viajan como `anon`. Aunque se activara RLS, no habría forma de saber quién es el usuario.
- **El `.env` se empaqueta y se publica.** `pubspec.yaml` lo declara como asset y `build/web/assets/.env` existe. Hoy solo contiene claves públicas/publishable, pero el patrón es incorrecto y contradice el objetivo del proyecto.
- **No hay reglas de Storage en el repositorio** ni configuración de Firebase Hosting (`firebase.json`, `.firebaserc`, `storage.rules`). Las URLs de descarga de Firebase Storage son bearer tokens: quien tenga la URL accede al archivo.
- **El APK release se firma con la clave de debug** y `AndroidManifest.xml` no desactiva backups.
- **Hay bugs funcionales serios:** el historial solo carga los 100 mensajes más antiguos; al cambiar de sala hay condiciones de carrera; el auto-scroll impide leer historial; la presencia no es en vivo; el registro puede dejar un usuario de Firebase sin perfil; la voz no funciona en web y acumula audio sin límite en memoria.
- **La documentación promete más de lo que existe:** Google Sign-In, recuperación de contraseña, búsqueda, scroll infinito, notificaciones push reales, confirmaciones de lectura, archivos/documentos, enlace a mapa, bottom nav móvil y menú long-press no están implementados o están solo parcialmente.

**Regla de oro:** primero se conecta la identidad Firebase → Supabase y se comprueba que el JWT llega con `role: authenticated`; **después** se activa RLS. Si se invierte el orden, la app deja de mostrar datos y parece “rota” sin dar errores claros.

---

## 2. Tabla de hallazgos

Severidades: **Crítica** (explotable ahora / bloquea seguridad), **Alta** (impacto directo o requisito incumplido), **Media** (bug funcional relevante), **Baja** (calidad/robustez).

| ID | Sev. | Tipo | Hallazgo | Referencia | Acción |
| :--- | :--- | :--- | :--- | :--- | :--- |
| SEC-01 | Crítica | RLS | RLS deshabilitado en todas las tablas públicas; `anon` lee y escribe | Supabase real; `PLAN...md:121-180` | Sección 8 |
| SEC-02 | Crítica | Auth | Supabase no usa el token de Firebase; todo va como `anon` | `lib/core/services/supabase_service.dart:11-19` | Sección 9.1 |
| SEC-03 | Crítica | Identidad | `sender_id`, `user_id`, `created_by` se confían del cliente | `supabase_service.dart:100-118,151-180`; `chat_provider.dart:116-198` | Sección 8.7 |
| SEC-04 | Alta | Secretos | `.env` empaquetado como asset y servido en web | `pubspec.yaml:73-74`; `build/web/assets/.env` | Sección 9.2 |
| SEC-05 | Alta | Storage | Sin `storage.rules`; sin límites de tamaño/tipo; URLs bearer | `storage_service.dart:8-52`; repo sin reglas | Sección 10.1 |
| SEC-06 | Alta | Android | Release firmado con debug keystore; backup activo | `android/app/build.gradle.kts:33-39`; `AndroidManifest.xml:8-11` | Sección 10.3 |
| SEC-07 | Alta | Validación | Sin límites de longitud/tipo/tamaño; spam y abuso posibles | `supabase_service.dart:74-118`; `chat_input_bar.dart:45-74` | Sección 8.4; 9.10 |
| SEC-08 | Alta | Errores | `catch` silenciosos ocultan fallos de red/permisos y dejan estado vacío | `supabase_service.dart:22-98,151-229` | Sección 9.3 |
| SEC-09 | Media | Realtime | `typing` es broadcast público y el nombre se toma del payload (suplantable) | `supabase_service.dart:197-229` | Sección 9.7 |
| SEC-10 | Media | FCM | Token FCM solo se imprime; no se guarda ni se envían notificaciones | `main.dart:28-45` | Sección 9.9 |
| BUG-01 | Alta | Historial | Solo devuelve los 100 mensajes **más antiguos** | `supabase_service.dart:85-98` | Sección 9.4 |
| BUG-02 | Alta | Concurrencia | Cambiar de sala rápido mezcla mensajes/suscripciones | `chat_provider.dart:59-104` | Sección 9.5 |
| BUG-03 | Alta | UX | Auto-scroll al fondo en cada build; imposible leer historial | `home_screen.dart:43-48` | Sección 9.11 |
| BUG-04 | Media | UI | El drawer móvil no se cierra de forma fiable | `channel_sidebar.dart:89-95` | Sección 9.12 |
| BUG-05 | Media | Presencia | `is_online` solo se actualiza en login/logout; no hay heartbeat ni lifecycle | `auth_service.dart:39-62`; `supabase_service.dart:40-47` | Sección 9.6 |
| BUG-06 | Alta | Auth | Registro no atómico; perfil puede quedar sin crear | `auth_service.dart:11-37` | Sección 9.8 |
| BUG-07 | Alta | Auth | `AuthGate` puede re-inicializar en bucle si el perfil no existe | `main.dart:108-115`; `chat_provider.dart:33-47` | Sección 9.8 |
| BUG-08 | Media | Estado | `initializeUser` puede quedarse en `isLoading=true` si algo falla | `chat_provider.dart:33-47` | Sección 9.8 |
| BUG-09 | Media | Typing | Se emite “escribiendo” en cada tecla, sin debounce ni stop al limpiar | `chat_input_bar.dart:222-224`; `chat_provider.dart:106-114` | Sección 9.7 |
| BUG-10 | Media | Reacciones | `select` + `insert/delete` no atómico; violaciones unique silenciadas | `supabase_service.dart:151-180` | Sección 9.13 |
| BUG-11 | Alta | Voz | Web sin soporte AAC stream; se guarda ADTS como `.m4a`; memoria sin límite | `voice_record_dialog.dart:33-87`; `storage_service.dart:40-52` | Sección 9.10 |
| BUG-12 | Media | Archivos | MIME por extensión (`image/jpg`), nombre sin sanear, sin tamaño máximo | `chat_input_bar.dart:55-63`; `storage_service.dart:8-37` | Sección 9.10 |
| BUG-13 | Media | Perfil | Diálogo sin scroll; overflow con teclado; avatar se sube al instante | `profile_dialog.dart:38-73,110-290` | Sección 9.14 |
| BUG-14 | Media | Audio | Varios reproductores suenan a la vez; listeners sin cancelar | `message_bubble.dart:309-360` | Sección 9.15 |
| BUG-15 | Media | Salas | `createRoom` no registra creador/miembro, permite duplicados/vacíos | `supabase_service.dart:74-82`; `chat_provider.dart:200-205` | Sección 9.16 |
| BUG-16 | Media | Realtime | Cada evento refetchea todo; reacciones de cualquier sala refrescan la actual | `supabase_service.dart:121-148`; `chat_provider.dart:74-81` | Sección 9.5 |
| BUG-17 | Baja | UI | Vista vacía aparece aunque la sala esté cargando (`isLoading` solo global) | `home_screen.dart:105-120`; `chat_provider.dart:59-71` | Sección 9.5 |
| BUG-18 | Media | Features | Read receipts, FCM, búsqueda, scroll infinito, archivos, mapa, bottom nav y long-press no existen | `README.md:41-55`; `PLAN...md:67-75,103-111` | Sección 5 |
| BUG-19 | Baja | Config | `main` no valida variables ni muestra error de arranque | `main.dart:17-58`; `supabase_service.dart:11-19` | Sección 9.17 |
| BUG-20 | Baja | Web | `index.html` y `manifest.json` genéricos; sin service worker de FCM | `web/index.html:21,32`; `web/manifest.json:2-9` | Sección 10.4 |
| BUG-21 | Baja | Tests | No hay tests de RLS, provider, concurrencia, auth ni Storage | `test/` | Sección 11 |
| BUG-22 | Media | UX | Se pierde el texto del mensaje si el envío falla (`clear()` antes del `await`) | `chat_input_bar.dart:27-43` | Sección 9.18 |

---

## 3. Bloqueantes de seguridad (detalle)

### SEC-01 — RLS deshabilitado (confirmado empíricamente)

**Qué se verificó (solo lecturas y escrituras fallidas/no-op, sin crear ni borrar datos):**

| Prueba | Resultado | Interpretación |
| :--- | :--- | :--- |
| `GET /rest/v1/rooms?select=name` con la publishable key | `200` con el canal existente | `anon` puede leer |
| `POST /rest/v1/messages` con `room_id`/`sender_id` inexistentes | Error de FK, **no** `401/403` | `anon` llega al motor SQL |
| `POST /rest/v1/rooms` con `name: null` | Error `not-null`, **no** de permisos | `anon` puede insertar |
| `POST /rest/v1/profiles` con `id: null` | Error `not-null`, **no** de permisos | `anon` puede insertar |
| `PATCH /rest/v1/rooms?id=eq.<uuid>` con cuerpo no-op | `204 No Content` | `anon` puede actualizar |

**Conclusión:** las políticas RLS no existen o no están habilitadas. La publishable/anon key es pública por diseño; **la única barrera real es RLS**, y hoy no está puesta.

**Riesgo:** cualquiera que extraiga la clave del APK/web (es trivial) puede leer todos los perfiles, mensajes, reacciones y salas, insertar mensajes suplantando a otros, borrar/alterar datos y consumir cuota.

**Acción:** sección 8 completa, en el orden indicado.

---

### SEC-02 — Supabase no autentica con Firebase

`lib/core/services/supabase_service.dart:11-19`:

```dart
await Supabase.initialize(
  url: url,
  publishableKey: anonKey,
);
```

No hay `accessToken`, no se llama a `realtime.setAuth`, y `AuthService` solo usa Firebase para el login local. Resultado: PostgREST y Realtime ejecutan todo como `anon`. Aunque mañana se activen las políticas `to authenticated`, **ninguna** aplicaría.

**Acción:** sección 9.1. Requisitos previos en Supabase/Firebase:

1. En Supabase: **Authentication → Third-Party Auth → Add provider → Firebase**, con el Project ID de Firebase.
2. En Firebase: asignar el custom claim `role: "authenticated"` a todos los usuarios (bloqueantes de Identity Platform o Cloud Function `onCreate` + backfill con Admin SDK). Sin ese claim, Supabase sigue usando `anon`.
3. En el cliente: `accessToken: () => FirebaseAuth.instance.currentUser?.getIdToken()` y `realtime.setAuth(token)`.
4. Tras el registro, forzar `getIdToken(true)` porque la Cloud Function `onCreate` es asíncrona y el primer token no trae el claim.

**Verificación:** el JWT debe contener `"role": "authenticated"` y `"sub": "<uid de Firebase>"`. En SQL, `auth.jwt() ->> 'role'` debe devolver `authenticated`. Si devuelve `null`, RLS no funcionará.

---

### SEC-03 — Identidad confiada al cliente

El cliente envía `senderId`, `userId` y `created_by` en el body:

- `supabase_service.dart:100-118` (`sendMessage` recibe `senderId`).
- `supabase_service.dart:151-180` (`toggleReaction` recibe `userId`).
- `chat_provider.dart:116-198` toma el id de `_currentUserProfile` (dato de la tabla `profiles`, no del JWT).

Hoy, con RLS apagado, cualquiera puede insertar `sender_id` de otra persona. Con RLS bien hecho, las políticas `WITH CHECK (sender_id = current_firebase_uid())` lo bloquean, y además conviene un trigger `BEFORE INSERT` que **sobrescriba** el valor para que ni siquiera dependa de que el cliente mande el campo correcto.

**Acción:** sección 8.7 (triggers) + sección 8.6 (políticas). No confiar en ningún id de usuario que venga del cliente.

---

### SEC-04 — `.env` empaquetado y publicado

`pubspec.yaml:73-74`:

```yaml
assets:
  - .env
```

Evidencia: `build/web/assets/.env` existe (410 bytes) y aparece en `AssetManifest.json`. En el APK también va dentro de `assets/flutter_assets/.env`.

Hoy el archivo contiene solo claves públicas/publishable (Supabase anon/publishable y Firebase API key), que están diseñadas para ser públicas. **No es una fuga de `service_role` ni de una clave privada**, pero:

- Contradice el requisito del proyecto (“ninguna clave ni archivo sensible expuesto”).
- Expone URL de proyecto, sender ID y configuración que no hacen falta en el cliente.
- Si alguien añade mañana una clave privada al `.env`, se publica automáticamente.
- El build web antiguo sigue sirviendo el archivo hasta que se limpie.

**Acción:** sección 9.2 (eliminar `flutter_dotenv` del runtime de producción, usar `--dart-define`/`--dart-define-from-file`).

---

### SEC-05 — Firebase Storage sin reglas versionadas

No existen `storage.rules`, `firebase.json` ni `.firebaserc` en el repositorio. `StorageService` sube avatares, imágenes y audios con `putData` y devuelve `getDownloadURL()`. Sin reglas:

- Cualquier usuario autenticado (o cualquiera, según la configuración del bucket) puede escribir en cualquier ruta.
- No hay límite de tamaño, tipo ni cantidad.
- Las URLs de descarga de Firebase son **bearer tokens**: quien tenga la URL accede al archivo aunque las reglas restrinjan la lectura. Si un mensaje con la URL se filtra, el archivo queda accesible hasta revocar el token.
- `avatars/$userId.$extension` y `chat_media/$roomId/${timestamp}_$fileName` usan nombres controlados por el cliente.

**Acción:** sección 10.1. Además, validar pertenencia a la sala en el servidor (Edge Function con signed upload URL) si se quiere aislamiento real; las reglas de Storage no pueden consultar Supabase directamente.

---

### SEC-06 — Release con debug key y backups activos

`android/app/build.gradle.kts:33-39` firma `release` con `signingConfigs.getByName("debug")`. Eso permite instalar el APK, pero:

- La clave de debug es pública y compartida; cualquiera puede firmar un APK “actualizado” con el mismo applicationId si consigue la clave (la de debug es conocida).
- No sirve para distribución real ni para Firebase App Distribution/Play Store.
- `AndroidManifest.xml:8-11` no define `android:allowBackup="false"`; los datos de la app (incluido el estado de Firebase Auth) pueden incluirse en backups del dispositivo.

**Acción:** sección 10.3.

---

### SEC-07 — Sin validación ni límites

No hay límites en:

- Texto del mensaje (se puede enviar megabytes).
- Nombre de canal (`createRoom` solo reemplaza espacios; puede quedar vacío o gigante).
- Nombre/bio de perfil.
- Tamaño/tipo de imagen, audio o avatar.
- Coordenadas (no se valida rango).
- Frecuencia de envío (spam).

**Acción:** validar en Dart (UX) **y** en Postgres (última línea). Sección 8.4.

---

### SEC-08 — Errores silenciados

Patrón repetido en `supabase_service.dart`:

```dart
} catch (_) {
  return [];
}
```

o

```dart
} catch (_) {}
```

Consecuencias:

- Un fallo de red se muestra como “canal vacío”, no como error.
- Un fallo de permisos (cuando se active RLS) se verá como “no hay mensajes”.
- Un fallo al actualizar presencia/reacción/lectura no se informa.
- Es imposible diagnosticar en producción.

**Acción:** sección 9.3. Las capas de datos deben **lanzar** errores tipados; el provider decide cómo mostrarlos.

---

## 4. Bugs funcionales (detalle)

### BUG-01 — Historial truncado a los 100 más antiguos

`lib/core/services/supabase_service.dart:85-98`:

```dart
.order('created_at', ascending: true)
.limit(limit);
```

Con `ascending: true` y `limit: 100`, Supabase devuelve los **primeros** 100 mensajes de la sala, no los últimos. En un canal activo, los mensajes nuevos nunca aparecen al abrir la sala (solo llegan por Realtime mientras está abierta).

**Solución:** ordenar descendente, limitar, y revertir en memoria; después implementar paginación por cursor (`before`) para el historial. Sección 9.4.

---

### BUG-02 — Condición de carrera al cambiar de sala

`chat_provider.dart:59-104`:

- `selectRoom` no cancela la petición anterior de `getMessages`.
- El callback de Realtime captura `room.id` y hace `getMessages(room.id)` sin comprobar si la sala sigue activa.
- `_cleanupSubscriptions()` se llama después de fijar `_activeRoom`, pero una petición en vuelo puede terminar después y sobrescribir `_messages`.
- Si el usuario pulsa rápido canal A → B → A, la respuesta de A vieja puede pisar la de A nueva.

**Solución:** token de petición (`int _roomRequest`), comprobar `request == _roomRequest && _activeRoom?.id == roomId` antes de asignar, y debounce de recargas. Sección 9.5.

---

### BUG-03 — Auto-scroll forzado en cada build

`home_screen.dart:43-48`:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (_scrollController.hasClients) {
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }
});
```

Esto se ejecuta en **cada** build (incluido el rebuild por typing, presencia o reacciones), no solo cuando llega un mensaje. El usuario no puede leer historial: cualquier cambio lo devuelve al fondo.

**Solución:** capturar si el usuario estaba cerca del fondo antes del cambio y solo desplazar en ese caso; usar `animateTo` y detectar crecimiento real del número de mensajes. Sección 9.11.

---

### BUG-04 — Drawer móvil no se cierra

`channel_sidebar.dart:89-95`:

```dart
chatProvider.selectRoom(room);
if (Navigator.of(context).canPop()) {
  Navigator.of(context).pop();
}
```

`Navigator.canPop()` puede ser `true` por la ruta de la app (no por el drawer), y el `context` es el del `ChannelSidebar`, no el del `Scaffold`. El resultado depende del árbol y a veces no cierra el drawer o hace un pop de la pantalla equivocada.

**Solución:** `Scaffold.maybeOf(context)?.closeDrawer();` o pasar un callback desde `HomeScreen` que use su propio `ScaffoldState`. Sección 9.12.

---

### BUG-05 — Presencia no es en vivo

- `AuthService.loginWithEmail` pone `is_online = true` (`auth_service.dart:49-51`).
- `AuthService.signOut` pone `false` (`auth_service.dart:56-61`).
- No hay actualización al pasar a background/foreground, no hay heartbeat, no hay suscripción a cambios de `profiles`.
- `MembersSidebar` solo se reconstruye si el provider notifica; `loadProfiles()` no se vuelve a llamar al volver a la app.
- Si la app se cierra abruptamente, el usuario queda “en línea” para siempre.

**Solución:** `AppLifecycleListener` + heartbeat + Realtime Presence (recomendado) o suscripción a `profiles`. Sección 9.6.

---

### BUG-06 — Registro no atómico

`auth_service.dart:11-37`:

1. Crea el usuario en Firebase.
2. Actualiza el display name.
3. Hace `upsert` del perfil en Supabase.

Si el paso 3 falla (red, RLS, timeout), el usuario queda creado en Firebase pero sin perfil. En el siguiente login, `getProfile` devuelve `null`, `initializeUser` no lanza error, y el chat queda sin `currentUserProfile` → `sendTextMessage` retorna silenciosamente (`chat_provider.dart:116-125`). El usuario puede iniciar sesión pero no enviar nada.

**Solución:** crear perfil y claim en una Cloud Function `onCreate` con Admin SDK (fuente única), o hacer un fallback idempotente en el login que recree el perfil si falta. No borrar la cuenta ante un fallo de red. Sección 9.8.

---

### BUG-07 — `AuthGate` puede entrar en bucle

`main.dart:108-115`:

```dart
if (chatProvider.currentUserProfile == null ||
    chatProvider.currentUserProfile?.id != user.uid) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    chatProvider.initializeUser(user.uid);
  });
}
```

Si el perfil no existe o `getProfile` falla, `currentUserProfile` sigue `null`. Cada rebuild vuelve a programar `initializeUser`, que hace `notifyListeners()` varias veces → nuevo rebuild → nueva llamada. Es un bucle de red y de frames.

**Solución:** estado `_initializedUserId` en `AuthGate` (StatefulWidget) o `_initializingUserId` en el provider; inicializar una sola vez por UID y mostrar un botón de reintento si falla. Sección 9.8.

---

### BUG-08 — `initializeUser` se queda cargando si falla

`chat_provider.dart:33-47` no tiene `try/catch/finally`. Si `getProfile`, `loadRooms`, `loadProfiles` o `selectRoom` lanzan, `_isLoading` queda `true` y la UI muestra el spinner para siempre.

**Solución:** `try/catch/finally`, estado de error y `notifyListeners` en `finally`. Sección 9.8.

---

### BUG-09 — “Escribiendo…” sin control

`chat_input_bar.dart:222-224` llama a `notifyTyping(val.isNotEmpty)` en **cada** pulsación. Eso envía un broadcast por tecla. Además:

- Al borrar todo el texto, envía `false` una vez, pero no hay temporizador de “dejar de escribir”.
- Si el usuario cierra la pantalla sin enviar, el receptor puede quedarse con “está escribiendo…” hasta que expire el timer local de 3 s.
- El nombre se toma del payload (`supabase_service.dart:206`), así que un cliente malicioso puede decir que “otro” está escribiendo.

**Solución:** debounce/throttle y canal privado con identidad del JWT. Sección 9.7.

---

### BUG-10 — Toggle de reacción no atómico

`supabase_service.dart:151-180` hace `select` → si existe `delete`, si no `insert`. Dos taps rápidos pueden:

- Insertar dos veces → violación de PK `(message_id, user_id, reaction)` silenciada por `catch (_) {}`.
- Borrar y luego insertar en orden invertido → reacción inconsistente.

**Solución:** RPC `toggle_reaction` en Postgres (atómico) o `insert ... on conflict do nothing` + `delete ... returning`. Sección 9.13.

---

### BUG-11 — Notas de voz: web roto y memoria ilimitada

`voice_record_dialog.dart:49-55`:

```dart
final stream = await _recorder.startStream(
  const RecordConfig(encoder: AudioEncoder.aacLc),
);
_streamSub = stream.listen((chunk) {
  _audioChunks.addAll(chunk);
});
```

Problemas:

1. **Web:** `record` 7.1.2 / `record_web` 2.1.3 **no soporta AAC en stream** (la matriz de compatibilidad deja `aacLc` vacío para web en Stream; solo `pcm16bits`). En web esto falla o queda sin datos. La app igualmente intenta subir.
2. **Formato:** el AAC en stream es **ADTS** (raw AAC con cabeceras ADTS), no un contenedor MP4/M4A. `storage_service.dart:45-48` lo guarda como `$timestamp.m4a` con `audio/m4a`; el MIME correcto para ADTS sería `audio/aac` y la extensión `.aac` (o convertir a m4a de verdad).
3. **Memoria:** `_audioChunks.addAll(chunk)` sin límite. Una grabación larga puede consumir toda la memoria del dispositivo/web.
4. **SnackBar tras `pop`:** en `_startRecording` (líneas 36-44 y 65-73) se hace `Navigator.pop()` y luego `ScaffoldMessenger.of(context).showSnackBar(...)` con un contexto ya desmontado; puede lanzar o no mostrarse.
5. **`stop()` en stream:** no devuelve archivo; el código ignora el valor. Para móvil conviene `start(path: ...)` y leer el archivo.

**Solución:** sección 9.10.

---

### BUG-12 — MIME y nombres de archivo

`chat_input_bar.dart:55-63`:

```dart
final ext = name.split('.').last.toLowerCase();
mimeType: 'image/${ext.isEmpty ? 'jpeg' : ext}',
```

- `foo.jpg` → `image/jpg` (no estándar; debe ser `image/jpeg`).
- `foo.heic` → `image/heic` (no soportado por muchos navegadores; `CachedNetworkImage` puede fallar).
- `foo` sin extensión → `image/jpeg` pero el archivo no es JPEG.
- `fileName` se concatena sin sanear en `storage_service.dart:30`; caracteres como `/`, `..` o espacios pueden crear rutas inesperadas.

**Solución:** allowlist de MIME/extensión, `lookupMimeType` del paquete `mime`, y sanitizar el nombre. Sección 9.10.

---

### BUG-13 — Diálogo de perfil con overflow y avatar inmediato

`profile_dialog.dart:115-124` usa `Dialog` + `ConstrainedBox(maxWidth: 440)` + `Column` sin scroll. En un móvil con teclado abierto, el contenido supera la altura y aparece el clásico “A RenderFlex overflowed”.

Además, `_pickAndUploadAvatar` (líneas 38-73) sube y guarda el avatar **al instante**, antes de que el usuario pulse “Guardar cambios”. Si cancela, el avatar ya cambió. Tampoco hay confirmación de tamaño/tipo.

**Solución:** `SingleChildScrollView` + `maxHeight` + `viewInsets`; guardar el avatar pendiente en memoria y subirlo solo al guardar. Sección 9.14.

---

### BUG-14 — Varios audios a la vez y listeners sin cancelar

`message_bubble.dart:318-343`: cada `_VoicePlayerWidget` crea su propio `AudioPlayer` y no hay coordinación. Si el usuario pulsa play en dos mensajes, suenan simultáneamente. Los `StreamSubscription` de `onPlayerStateChanged`, `onDurationChanged` y `onPositionChanged` no se guardan ni se cancelan; `dispose()` solo llama a `_player.dispose()`.

**Solución:** un `AudioPlayer` compartido a nivel de pantalla/provider, o un `ValueNotifier<String?> playingMessageId`; guardar y cancelar las suscripciones. Sección 9.15.

---

### BUG-15 — Creación de salas incompleta

`supabase_service.dart:74-82`:

```dart
final cleanName = name.trim().replaceAll(' ', '-').toLowerCase();
final response = await client
    .from('rooms')
    .insert({'name': cleanName, 'is_group': true})
    .select()
    .single();
```

- No guarda `created_by`.
- No inserta en `room_members`.
- No valida que `cleanName` no quede vacío (nombre compuesto solo de espacios → `''`).
- No evita duplicados (no hay unique index).
- No valida longitud ni caracteres.
- `is_group: true` no significa “público”; el DDL lo define `default false` y no se usa para permisos.

**Solución:** RPC `create_room` + constraint único + trigger de owner. Sección 9.16.

---

### BUG-16 — Realtime ineficiente y con fuga de alcance

`supabase_service.dart:121-148`:

- La suscripción a `message_reactions` **no tiene filtro** (no se puede filtrar por `room_id` en una tabla relacionada). Cualquier reacción en cualquier sala dispara `onDataChanged()` y hace `getMessages` de la sala actual.
- Cada INSERT/UPDATE/DELETE hace un refetch completo de hasta 100 mensajes.
- Los canales se eliminan en `_cleanupSubscriptions`, pero una recarga en vuelo puede seguir viva.

**Solución:** añadir `room_id` denormalizado a `message_reactions` y `message_reads` (con trigger), filtrar por sala, y actualizar el estado local con el payload o hacer un refetch debounced. Sección 9.5.

---

### BUG-17 — “Canal vacío” durante la carga

`chat_provider.dart:59-71` no pone `_isLoading = true` al cambiar de sala; `home_screen.dart:105-120` decide entre spinner y `_buildEmptyChannelView` usando `chatProvider.isLoading`, que solo es `true` durante `initializeUser`. Al cambiar de canal, se ve “¡Sé el primero en enviar un mensaje!” mientras llegan los datos.

**Solución:** estado de carga por sala y error por sala. Sección 9.5.

---

### BUG-18 — Funcionalidades anunciadas vs reales

Ver sección 5.

---

### BUG-19 — Arranque sin validación ni manejo de error

`main.dart:17-58` asume que `.env`, Firebase y Supabase están bien. Si falta una variable, `dotenv.load` o `Supabase.initialize` lanzan antes de `runApp` y el usuario ve una pantalla en blanco o un crash. No hay `ErrorWidget.builder`, `FlutterError.onError` ni `runZonedGuarded`.

**Solución:** validar configuración y mostrar una pantalla de error clara; sección 9.17.

---

### BUG-20 — Web genérica

`web/index.html:21` y `:32`, `web/manifest.json:2-9` siguen con “A new Flutter project.” y `discord_epn`. No hay `web/firebase-messaging-sw.js` para FCM web, ni `firebase.json` con headers/rewrites. Sección 10.4.

---

### BUG-21 — Cobertura de pruebas insuficiente

`test/` solo tiene:

- `models_and_constants_test.dart`: serialización de modelos y colores.
- `widget_test.dart`: render de `LoginScreen`.

No hay pruebas de:

- Provider (cambios de sala, errores, concurrencia, envío).
- Auth (registro/perfil faltante).
- RLS ni Storage rules.
- Widgets críticos (`ChatInputBar`, `ProfileDialog`, drawer, audio).
- Paginación.

Sección 11.

---

### BUG-22 — Pérdida del texto si falla el envío

`chat_input_bar.dart:27-43` limpia el campo (`_controller.clear()`) **antes** de `await sendTextMessage(text)`. Si la red falla, el mensaje no se envió y el usuario ya perdió lo que había escrito; el `SnackBar` de error solo informa, no restaura el contenido.

**Solución:** limpiar solo después del éxito; si falla, dejar el texto intacto (o restaurarlo si se limpió de forma optimista) y devolver el foco al campo. Sección 9.18.

---

## 5. Funcionalidades anunciadas vs implementadas

| Promesa (README/PLAN/CHECKPOINT) | Estado real | Evidencia |
| :--- | :--- | :--- |
| Google Sign-In | **No implementado** | Solo email/password en `auth_service.dart`; no hay `google_sign_in`. |
| Recuperación de contraseña | **No implementado** | No hay `sendPasswordResetEmail` ni pantalla. |
| Búsqueda de canales/mensajes | **No implementado** | No hay campo de búsqueda en `channel_sidebar.dart` ni query `ilike`. |
| Scroll infinito / paginación | **No implementado** | `getMessages` con límite fijo; no hay carga al hacer scroll. |
| Envío de archivos/documentos | **Parcial** | Solo imágenes; el tipo `file` existe en el modelo/DDL pero no hay UI. |
| Enlace a Google Maps | **Parcial** | `message_bubble.dart:239-256` muestra un badge “Punto en Mapa EPN” sin acción; no hay `url_launcher`. |
| Notificaciones push reales | **Parcial/no** | `main.dart:28-45` pide permiso y obtiene token, pero no lo guarda, no maneja `onMessage`/`onBackgroundMessage`, no hay envío desde servidor ni service worker web. |
| Confirmaciones de lectura | **No** | `markMessageRead` existe (`supabase_service.dart:183-194`) pero no se llama desde ningún widget; no hay UI de checkmarks. |
| Presencia en vivo | **Parcial** | Solo login/logout; no hay lifecycle/heartbeat/Realtime de perfiles. |
| Bottom nav móvil (`Chats`, `Notificaciones`, `Tú`) | **No** | En móvil solo hay `Drawer` y `endDrawer` (`home_screen.dart:53-127`). |
| Menú long-press (editar/borrar mensaje) | **No** | No hay `onLongPress` en `message_bubble.dart`. |
| Lightbox de imágenes | **Sí** | `image_viewer_dialog.dart`. |
| Reacciones con conteo | **Sí, con race** | `message_bubble.dart:98-157`; `supabase_service.dart:151-180`. |
| Notas de voz | **Parcial** | Funciona en móvil con matices; web roto; formato/MIME incorrectos. |
| “Escribiendo…” | **Sí, sin throttling** | Broadcast en cada tecla. |
| Perfil editable | **Sí** | `profile_dialog.dart`. |
| Creación de canales | **Sí, incompleta** | Sin owner/miembro/duplicados. |
| Feed en tiempo real | **Sí, con refetch total** | `subscribeToRoomMessages`. |

**Acción:** o se implementa lo que falta, o se corrige README/CHECKPOINT/PLAN para no afirmar “13/13”. Para la entrega, lo más honesto es marcar explícitamente “parcial” y documentar el alcance.

---

## 6. Decisiones y supuestos de la remediación

Estas decisiones explican **por qué** las correcciones tienen la forma propuesta. Si Gemini se desvía de ellas, debe justificarlo y volver a probar RLS.

1. **Se mantiene Firebase Auth como proveedor de identidad** y Supabase Postgres/Realtime como backend de datos. No se migran usuarios a Supabase Auth en esta entrega.
2. **La identidad en Postgres es el claim `sub` del JWT de Firebase**, no `auth.uid()`. Los UID de Firebase son texto y no cumplen el formato UUID que exige `auth.uid()`.
3. **El claim `role: authenticated` se asigna en el servidor** (Cloud Function/bloqueante o Admin SDK + backfill). El cliente no puede autoasignarse ese claim; solo fuerza el refresh con `getIdToken(true)`.
4. **Primero se conecta el puente de autenticación y se verifica; después se activa RLS.** Invertir el orden deja la app sin datos y sin errores claros.
5. **Se conserva `is_public = true` en las salas existentes** para no romper el comportamiento actual (todos ven todos los canales). El modo estrictamente privado requiere backfill de membresías y UI de invitación, que hoy no existe.
6. **Storage sigue en Firebase Storage** en esta fase. Las reglas de la sección 10.1 son el mínimo; el aislamiento por sala real requiere Edge Function con signed URLs (opción B).
7. **Prioridad de ejecución:** primero lo explotable hoy (RLS, identidad, `.env`), luego los bugs que rompen el uso normal (historial, race de salas, registro/perfil), y al final la deuda de calidad (tests, web, documentación).
8. **Fuera de alcance:** pentest formal, pruebas en iOS, despliegue real del backend de FCM y migración completa de archivos a Supabase Storage.

---

## 7. Plan de corrección por fases

### Fase 0 — Preparación (sin cambios funcionales)

1. Crear rama `fix/security-audit`.
2. Hacer backup/export del esquema y datos de Supabase (Dashboard → Database → Backups, o `pg_dump`).
3. Ejecutar las consultas de diagnóstico de la sección 8.1 y guardar el resultado.
4. Añadir `config/` y `*.json` de configuración local al `.gitignore` (sin ignorar `pubspec`/`analysis_options`).
5. Confirmar que `.env` y `google-services.json` no están trackeados: `git ls-files | Select-String -Pattern '\.env$|google-services\.json'` no debe devolver nada.

### Fase 1 — Puente de autenticación Firebase → Supabase (NO activar RLS todavía)

1. Configurar Third-Party Auth de Firebase en Supabase.
2. Asignar el claim `role: authenticated` a todos los usuarios (Cloud Function + backfill).
3. Cambiar `SupabaseService.initialize` para usar `accessToken`.
4. Llamar a `realtime.setAuth` en login, registro, refresh y logout.
5. Forzar `getIdToken(true)` después del registro.
6. Verificar con una consulta autenticada que `auth.jwt() ->> 'role'` es `authenticated` y `sub` es el UID de Firebase.
7. **No continuar** si el rol sigue siendo `anon`.

### Fase 2 — Esquema y RLS

1. Ejecutar la limpieza de datos de la sección 8.1.
2. Añadir columnas, constraints, índices y triggers (sección 8.4-8.7).
3. Crear helpers y políticas (sección 8.6).
4. **Activar RLS en una transacción** y probar cada tabla con dos usuarios reales y con `anon`.
5. Verificar que `anon` recibe `401/403` o arrays vacíos, y que un usuario no puede leer/escribir datos de otro.
6. Añadir `room_id` denormalizado a reacciones/lecturas y filtros de Realtime.

### Fase 3 — Bugs funcionales y robustez

Orden sugerido:

1. `getMessages` (paginación/orden) — BUG-01.
2. `ChatProvider.selectRoom` (race, loading, errores) — BUG-02/08/17.
3. Auto-scroll — BUG-03.
4. Drawer — BUG-04.
5. Auth/registro/`AuthGate` — BUG-06/07.
6. Presencia — BUG-05.
7. Typing — BUG-09.
8. Reacciones — BUG-10.
9. Voz/MIME/archivos — BUG-11/12.
10. Perfil/audio — BUG-13/14.
11. Salas — BUG-15.
12. Realtime — BUG-16.
13. Pérdida de texto al fallar el envío — BUG-22.

### Fase 4 — Storage, Hosting y hardening

1. `storage.rules` + `firebase.json` + `.firebaserc`.
2. Reglas de tamaño/tipo; probar con el emulador de Storage.
3. Headers de seguridad y CSP en Hosting.
4. Quitar `.env` del bundle; reconstruir `build/web` y verificar que no existe `assets/.env`.
5. `web/firebase-messaging-sw.js` si se implementa FCM web.
6. Manifest/index con nombre y colores reales.

### Fase 5 — Release Android

1. Crear keystore de release y `android/key.properties` (ignorado).
2. Configurar `signingConfigs.release` y usarla en `buildTypes.release`.
3. `allowBackup=false`, `fullBackupContent=false`, `dataExtractionRules` para API 31+.
4. `usesCleartextTraffic=false`.
5. Compilar con `--obfuscate --split-debug-info=build/symbols`.
6. Verificar firma con `apksigner verify --print-certs`.

### Fase 6 — Funcionalidades pendientes (si el tiempo alcanza)

Orden por valor/riesgo:

1. Read receipts (ya hay tabla y método).
2. FCM real (token + Edge Function + background handler).
3. Scroll infinito (ya se prepara en Fase 3).
4. Búsqueda de canales/mensajes.
5. Envío de archivos.
6. Enlace a Google Maps.
7. Google Sign-In y recuperación de contraseña.
8. Bottom nav móvil y long-press.

---

## 8. Migración SQL de seguridad

> **Advertencia:** ejecutar en un proyecto de prueba primero. Varias sentencias fallan si hay datos que violan las restricciones. Hacer backup antes.

### 8.1. Diagnóstico y limpieza previa

```sql
-- ¿Qué tablas tienen RLS?
select schemaname, tablename, rowsecurity
from pg_tables
where schemaname = 'public'
order by tablename;

-- ¿Qué políticas existen?
select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- ¿Qué grants tiene anon?
select table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'anon' and table_schema = 'public'
order by table_name, privilege_type;

-- Duplicados de salas antes del unique index
select lower(name) as name, count(*)
from public.rooms
group by lower(name)
having count(*) > 1;

-- Datos que violarían las constraints
select id, char_length(content) as len from public.messages where content is not null and char_length(content) > 4000;
select id, char_length(display_name) as len from public.profiles where char_length(display_name) not between 3 and 32;
select id, name from public.rooms where name !~ '^[a-z0-9][a-z0-9-]{1,31}$';
select id, type, content, media_url from public.messages
where (type = 'text' and (content is null or btrim(content) = ''))
   or (type in ('image','file','audio') and media_url is null);
```

Limpieza sugerida (revisar antes de ejecutar; no borra filas, solo normaliza):

```sql
update public.messages
set content = left(content, 4000)
where content is not null and char_length(content) > 4000;

update public.profiles
set display_name = left(display_name, 32)
where char_length(display_name) > 32;

update public.profiles
set display_name = 'Usuario'
where char_length(display_name) < 3;

update public.rooms
set name = lower(regexp_replace(trim(name), '[^a-zA-Z0-9]+', '-', 'g'));

update public.rooms
set name = 'canal-' || substr(id::text, 1, 8)
where name is null or name = '' or name !~ '^[a-z0-9][a-z0-9-]{1,31}$';
```

Si hay duplicados de `lower(name)`, renombrar los duplicados antes de crear el índice único:

```sql
with ranked as (
  select id, lower(name) as n,
         row_number() over (partition by lower(name) order by created_at, id) as rn
  from public.rooms
)
update public.rooms r
set name = left(r.name, 26) || '-' || substr(r.id::text, 1, 4)
from ranked
where r.id = ranked.id and ranked.rn > 1;
```

### 8.2. Helper de identidad (Firebase UID)

**No usar `auth.uid()`**: devuelve `uuid` y los UID de Firebase son texto (28 caracteres alfanuméricos). Usar `auth.jwt() ->> 'sub'`.

```sql
create or replace function public.current_firebase_uid()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select nullif(auth.jwt() ->> 'sub', '');
$$;

revoke all on function public.current_firebase_uid() from public;
grant execute on function public.current_firebase_uid() to authenticated, service_role;
```

### 8.3. Columnas de ownership/auditoría

```sql
alter table public.profiles
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.rooms
  add column if not exists created_by text references public.profiles(id) on delete set null,
  add column if not exists is_public boolean not null default true,
  add column if not exists updated_at timestamptz not null default now();

alter table public.messages
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz;

alter table public.message_reactions
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists room_id uuid references public.rooms(id) on delete cascade;

alter table public.message_reads
  add column if not exists room_id uuid references public.rooms(id) on delete cascade;

-- Backfill de room_id en reacciones/lecturas existentes
update public.message_reactions r
set room_id = m.room_id
from public.messages m
where r.message_id = m.id and r.room_id is null;

update public.message_reads r
set room_id = m.room_id
from public.messages m
where r.message_id = m.id and r.room_id is null;
```

> `is_public = true` es importante para no romper la app actual: hoy todos los canales son visibles para todos. Si se quiere modo “solo miembros”, poner `is_public = false` y crear las membresías correspondientes antes de activar RLS.

### 8.4. Constraints e índices

```sql
-- Perfiles
alter table public.profiles
  add constraint profiles_display_name_len check (char_length(display_name) between 3 and 32) not valid,
  add constraint profiles_bio_len check (char_length(bio) <= 190) not valid;

-- Salas
alter table public.rooms
  add constraint rooms_name_format check (name ~ '^[a-z0-9][a-z0-9-]{1,31}$') not valid;

-- Mensajes
alter table public.messages
  add constraint messages_content_len check (content is null or char_length(content) <= 4000) not valid,
  add constraint messages_type_allowed check (type in ('text','image','file','location','audio')) not valid,
  add constraint messages_text_has_content check (type <> 'text' or (content is not null and btrim(content) <> '')) not valid,
  add constraint messages_media_required check (type not in ('image','file','audio') or media_url is not null) not valid,
  add constraint messages_location_bounds check (
    (latitude is null and longitude is null)
    or (latitude between -90 and 90 and longitude between -180 and 180)
  ) not valid;

-- Reacciones
alter table public.message_reactions
  add constraint reactions_len check (char_length(reaction) between 1 and 32) not valid;

-- Miembros
alter table public.room_members
  add constraint room_members_role check (role in ('owner','admin','member')) not valid;

-- Validar (después de limpiar datos)
alter table public.profiles validate constraint profiles_display_name_len;
alter table public.profiles validate constraint profiles_bio_len;
alter table public.rooms validate constraint rooms_name_format;
alter table public.messages validate constraint messages_content_len;
alter table public.messages validate constraint messages_type_allowed;
alter table public.messages validate constraint messages_text_has_content;
alter table public.messages validate constraint messages_media_required;
alter table public.messages validate constraint messages_location_bounds;
alter table public.message_reactions validate constraint reactions_len;
alter table public.room_members validate constraint room_members_role;

-- Índices
create index if not exists messages_room_created_idx
  on public.messages (room_id, created_at desc, id desc);
create index if not exists messages_sender_idx
  on public.messages (sender_id);
create index if not exists reactions_message_idx
  on public.message_reactions (message_id);
create index if not exists reactions_user_idx
  on public.message_reactions (user_id);
create index if not exists reactions_room_idx
  on public.message_reactions (room_id);
create index if not exists reads_user_idx
  on public.message_reads (user_id);
create index if not exists reads_room_idx
  on public.message_reads (room_id);
create index if not exists members_user_idx
  on public.room_members (user_id);
create index if not exists profiles_display_name_idx
  on public.profiles (lower(display_name));
create unique index if not exists rooms_name_lower_uidx
  on public.rooms (lower(name));
```

### 8.5. Triggers de integridad

```sql
-- updated_at
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists rooms_set_updated_at on public.rooms;
create trigger rooms_set_updated_at
before update on public.rooms
for each row execute function public.set_updated_at();

-- sender_id inmutable y forzado desde el JWT
create or replace function public.force_message_sender()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and public.current_firebase_uid() is not null then
    new.sender_id := public.current_firebase_uid();
  elsif tg_op = 'UPDATE' and new.sender_id is distinct from old.sender_id then
    raise exception 'sender_id es inmutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_force_sender on public.messages;
create trigger messages_force_sender
before insert or update on public.messages
for each row execute function public.force_message_sender();

-- user_id inmutable y forzado en reacciones
create or replace function public.force_reaction_user()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and public.current_firebase_uid() is not null then
    new.user_id := public.current_firebase_uid();
  elsif tg_op = 'UPDATE' and new.user_id is distinct from old.user_id then
    raise exception 'user_id es inmutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists reactions_force_user on public.message_reactions;
create trigger reactions_force_user
before insert or update on public.message_reactions
for each row execute function public.force_reaction_user();

-- user_id inmutable y forzado en lecturas
create or replace function public.force_read_user()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and public.current_firebase_uid() is not null then
    new.user_id := public.current_firebase_uid();
  elsif tg_op = 'UPDATE' and new.user_id is distinct from old.user_id then
    raise exception 'user_id es inmutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists reads_force_user on public.message_reads;
create trigger reads_force_user
before insert or update on public.message_reads
for each row execute function public.force_read_user();

-- room_id de reacciones/lecturas se deriva del mensaje
create or replace function public.set_reaction_room()
returns trigger
language plpgsql
as $$
begin
  select room_id into new.room_id from public.messages where id = new.message_id;
  return new;
end;
$$;

drop trigger if exists reactions_set_room on public.message_reactions;
create trigger reactions_set_room
before insert or update of message_id on public.message_reactions
for each row execute function public.set_reaction_room();

create or replace function public.set_read_room()
returns trigger
language plpgsql
as $$
begin
  select room_id into new.room_id from public.messages where id = new.message_id;
  return new;
end;
$$;

drop trigger if exists reads_set_room on public.message_reads;
create trigger reads_set_room
before insert or update of message_id on public.message_reads
for each row execute function public.set_read_room();

-- created_by de salas forzado desde el JWT
create or replace function public.force_room_creator()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and public.current_firebase_uid() is not null then
    new.created_by := public.current_firebase_uid();
  elsif tg_op = 'UPDATE' and new.created_by is distinct from old.created_by then
    raise exception 'created_by es inmutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists rooms_force_creator on public.rooms;
create trigger rooms_force_creator
before insert or update on public.rooms
for each row execute function public.force_room_creator();

-- El creador entra automáticamente como owner
create or replace function public.add_room_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.created_by is not null then
    insert into public.room_members(room_id, user_id, role)
    values (new.id, new.created_by, 'owner')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists rooms_add_owner on public.rooms;
create trigger rooms_add_owner
after insert on public.rooms
for each row execute function public.add_room_owner();

-- Las funciones de trigger no se invocan directamente; quitar EXECUTE a PUBLIC
revoke all on function public.set_updated_at() from public;
revoke all on function public.force_message_sender() from public;
revoke all on function public.force_reaction_user() from public;
revoke all on function public.force_read_user() from public;
revoke all on function public.set_reaction_room() from public;
revoke all on function public.set_read_room() from public;
revoke all on function public.force_room_creator() from public;
revoke all on function public.add_room_owner() from public;
grant execute on function public.add_room_owner() to service_role;
```

### 8.6. Helpers y políticas RLS

```sql
-- Acceso a sala: pública o miembro. SECURITY DEFINER para evitar recursión con RLS de rooms.
create or replace function public.can_access_room(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.rooms r
    where r.id = p_room_id
      and (
        r.is_public = true
        or exists (
          select 1
          from public.room_members m
          where m.room_id = r.id
            and m.user_id = public.current_firebase_uid()
        )
      )
  );
$$;

revoke all on function public.can_access_room(uuid) from public;
grant execute on function public.can_access_room(uuid) to authenticated, service_role;

-- Habilitar RLS
alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.message_reads enable row level security;

-- Quitar permisos al rol anónimo
revoke all on public.profiles, public.rooms, public.room_members,
  public.messages, public.message_reactions, public.message_reads
from anon;

-- Asegurar grants al rol autenticado
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.rooms to authenticated;
grant select, insert, update, delete on public.room_members to authenticated;
grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update, delete on public.message_reactions to authenticated;
grant select, insert, update, delete on public.message_reads to authenticated;

-- PROFILES
create policy profiles_select_authenticated
on public.profiles for select
to authenticated
using (true);

create policy profiles_insert_self
on public.profiles for insert
to authenticated
with check (id = public.current_firebase_uid());

create policy profiles_update_self
on public.profiles for update
to authenticated
using (id = public.current_firebase_uid())
with check (id = public.current_firebase_uid());

-- ROOMS
create policy rooms_select_accessible
on public.rooms for select
to authenticated
using (public.can_access_room(id));

create policy rooms_insert_creator
on public.rooms for insert
to authenticated
with check (created_by = public.current_firebase_uid());

create policy rooms_update_creator
on public.rooms for update
to authenticated
using (created_by = public.current_firebase_uid())
with check (created_by = public.current_firebase_uid());

create policy rooms_delete_creator
on public.rooms for delete
to authenticated
using (created_by = public.current_firebase_uid());

-- ROOM_MEMBERS
create policy members_select_room
on public.room_members for select
to authenticated
using (public.can_access_room(room_id));

create policy members_insert_owner
on public.room_members for insert
to authenticated
with check (
  -- El creador de la sala puede agregar a cualquier usuario.
  -- No se exige user_id = current_firebase_uid() para permitir invitaciones.
  exists (
    select 1 from public.rooms r
    where r.id = room_id
      and r.created_by = public.current_firebase_uid()
  )
);

create policy members_update_owner
on public.room_members for update
to authenticated
using (
  exists (
    select 1 from public.rooms r
    where r.id = room_id
      and r.created_by = public.current_firebase_uid()
  )
)
with check (
  exists (
    select 1 from public.rooms r
    where r.id = room_id
      and r.created_by = public.current_firebase_uid()
  )
);

create policy members_delete_self_or_owner
on public.room_members for delete
to authenticated
using (
  user_id = public.current_firebase_uid()
  or exists (
    select 1 from public.rooms r
    where r.id = room_id
      and r.created_by = public.current_firebase_uid()
  )
);

-- MESSAGES
create policy messages_select_room
on public.messages for select
to authenticated
using (public.can_access_room(room_id));

create policy messages_insert_room
on public.messages for insert
to authenticated
with check (
  sender_id = public.current_firebase_uid()
  and public.can_access_room(room_id)
);

create policy messages_update_own
on public.messages for update
to authenticated
using (sender_id = public.current_firebase_uid())
with check (sender_id = public.current_firebase_uid());

create policy messages_delete_own
on public.messages for delete
to authenticated
using (sender_id = public.current_firebase_uid());

-- REACTIONS
create policy reactions_select_room
on public.message_reactions for select
to authenticated
using (
  exists (
    select 1 from public.messages m
    where m.id = message_id
      and public.can_access_room(m.room_id)
  )
);

create policy reactions_insert_own
on public.message_reactions for insert
to authenticated
with check (
  user_id = public.current_firebase_uid()
  and exists (
    select 1 from public.messages m
    where m.id = message_id
      and public.can_access_room(m.room_id)
  )
);

create policy reactions_delete_own
on public.message_reactions for delete
to authenticated
using (user_id = public.current_firebase_uid());

-- READS
create policy reads_select_room
on public.message_reads for select
to authenticated
using (
  user_id = public.current_firebase_uid()
  or exists (
    select 1 from public.messages m
    where m.id = message_id
      and public.can_access_room(m.room_id)
  )
);

create policy reads_insert_own
on public.message_reads for insert
to authenticated
with check (
  user_id = public.current_firebase_uid()
  and exists (
    select 1 from public.messages m
    where m.id = message_id
      and public.can_access_room(m.room_id)
  )
);

create policy reads_update_own
on public.message_reads for update
to authenticated
using (user_id = public.current_firebase_uid())
with check (user_id = public.current_firebase_uid());
```

> **Nota:** si se prefiere un modelo estrictamente privado, poner `is_public = false` en todas las salas y crear membresías para todos los usuarios actuales antes de activar RLS. La app no tiene UI de “unirse a sala”, así que sin ese backfill los canales nuevos serían invisibles para los demás.

### 8.7. RPCs atómicas

```sql
-- Crear sala + owner en una sola operación
create or replace function public.create_room(p_name text)
returns public.rooms
language plpgsql
security invoker
set search_path = public
as $$
declare
  r public.rooms;
  clean text;
begin
  clean := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g'));
  if clean !~ '^[a-z0-9][a-z0-9-]{1,31}$' then
    raise exception 'Nombre de canal inválido' using errcode = '22023';
  end if;

  insert into public.rooms(name, created_by)
  values (clean, public.current_firebase_uid())
  returning * into r;

  return r;
end;
$$;

grant execute on function public.create_room(text) to authenticated, service_role;

-- Toggle de reacción atómico
create or replace function public.toggle_reaction(p_message_id uuid, p_reaction text)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  removed int;
begin
  delete from public.message_reactions
  where message_id = p_message_id
    and user_id = public.current_firebase_uid()
    and reaction = p_reaction;

  get diagnostics removed = row_count;
  if removed > 0 then
    return false; -- se quitó
  end if;

  insert into public.message_reactions(message_id, user_id, reaction)
  values (p_message_id, public.current_firebase_uid(), p_reaction)
  on conflict do nothing;

  return true; -- se agregó
end;
$$;

grant execute on function public.toggle_reaction(uuid, text) to authenticated, service_role;
```

### 8.8. Realtime

```sql
-- Publicar tablas (sin fallar si ya están publicadas)
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'message_reads'
  ) then
    alter publication supabase_realtime add table public.message_reads;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;
end $$;

-- Necesario para que los eventos DELETE incluyan room_id y para filtros por columna
alter table public.messages replica identity full;
```

> Tras cambiar RLS, el cliente debe llamar a `realtime.setAuth(token)` y volver a suscribirse. Si el token no está configurado, Realtime puede devolver “Unauthorized” o no entregar eventos.

### 8.9. Verificación rápida de RLS

```sql
-- Debe devolver true en todas
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in ('profiles','rooms','room_members','messages','message_reactions','message_reads');

-- Debe haber al menos una política por tabla
select tablename, count(*) as policies
from pg_policies
where schemaname = 'public'
group by tablename
order by tablename;

-- anon no debe tener privilegios
select table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'anon' and table_schema = 'public';
```

---

## 9. Correcciones en Dart (snippets)

> Los snippets son guías de implementación. Adaptar imports, nombres y manejo de estado al proyecto; no copiar sin compilar.

### 9.1. Conectar Firebase Auth con Supabase

**Paso previo (consola):**

1. Supabase → Authentication → Third-Party Auth → Firebase → Project ID.
2. Firebase → asignar custom claim `role: "authenticated"` (Cloud Function/bloqueante + backfill).
3. Forzar refresh del token después del registro.

**`lib/core/config/app_config.dart`:**

```dart
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static void validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Faltan SUPABASE_URL y/o SUPABASE_ANON_KEY. '
        'Ejecuta con --dart-define-from-file=config/dev.json',
      );
    }
  }
}
```

**`supabase_service.dart`:**

```dart
static Future<void> initialize() async {
  AppConfig.validate();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
    accessToken: () async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      // getIdToken() refresca solo si está por expirar.
      return user.getIdToken();
    },
  );

  // Realtime no usa el callback de accessToken: hay que empujarle el token.
  FirebaseAuth.instance.idTokenChanges().listen((user) async {
    final token = await user?.getIdToken();
    await Supabase.instance.client.realtime.setAuth(token);
  });
}
```

**Después de login/registro (en `AuthService` o en el `AuthGate`):**

```dart
Future<void> _syncRealtimeAuth(User user, {bool force = false}) async {
  final token = await user.getIdToken(force);
  await Supabase.instance.client.realtime.setAuth(token);
}
```

**Comprobar el claim (diagnóstico, no seguridad):**

```dart
import 'dart:convert';

bool hasAuthenticatedRole(String idToken) {
  final parts = idToken.split('.');
  if (parts.length != 3) return false;
  final payload = jsonDecode(
    utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
  ) as Map<String, dynamic>;
  return payload['role'] == 'authenticated';
}
```

Si `hasAuthenticatedRole` es `false`, **no** continúes con RLS: la app seguirá como `anon`. Muestra un mensaje de configuración y revisa la Cloud Function/backfill.

> **Importante:** `auth.uid()` no sirve con Firebase. Las políticas usan `auth.jwt() ->> 'sub'` (sección 8.2). El `sub` es un string de 28 caracteres, no un UUID.

---

### 9.2. Sacar el `.env` del bundle

**`pubspec.yaml`:** eliminar `- .env` de `assets` y la dependencia `flutter_dotenv` si ya no se usa.

**`.gitignore`:** añadir:

```gitignore
config/
*.dart_define.json
```

**`config/dev.example.json` (sí se versiona el ejemplo):**

```json
{
  "SUPABASE_URL": "https://tu-proyecto.supabase.co",
  "SUPABASE_ANON_KEY": "tu-publishable-key"
}
```

**Ejecución local:**

```powershell
flutter run --dart-define-from-file=config/dev.json
```

**Build web/APK:**

```powershell
flutter build web --release --dart-define-from-file=config/prod.json
flutter build apk --release --dart-define-from-file=config/prod.json
```

**Limpieza obligatoria del build viejo:**

```powershell
Remove-Item -Recurse -Force build
flutter build web --release --dart-define-from-file=config/prod.json
Test-Path build/web/assets/.env   # debe ser False
```

> No basta con borrar `.env` del repo: hay que reconstruir el build y, si ya se desplegó, volver a desplegar Hosting. Revisa también el historial de git por si alguna vez se commiteó una clave privada (en este repo `.env` nunca estuvo trackeado, pero verifica con `git log --all -- .env`).

---

### 9.3. Errores tipados en vez de `catch` silencioso

**`lib/core/errors/app_exception.dart`:**

```dart
class AppException implements Exception {
  final String message;
  final Object? cause;
  const AppException(this.message, [this.cause]);

  @override
  String toString() => message;
}
```

**Patrón para `SupabaseService.getMessages`:**

```dart
static Future<List<MessageModel>> getMessages(
  String roomId, {
  int limit = 50,
  DateTime? before,
}) async {
  try {
    var query = client
        .from('messages')
        .select('*, profiles(*), message_reactions(*)')
        .eq('room_id', roomId);

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }

    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
        .toList()
        .reversed
        .toList();
  } on PostgrestException catch (e) {
    throw AppException(
      e.code == '42501'
          ? 'No tienes permiso para ver este canal.'
          : 'No se pudo cargar el historial (${e.code ?? 'error'}).',
      e,
    );
  } catch (e) {
    throw AppException('Error de red al cargar el historial.', e);
  }
}
```

**En el provider:**

```dart
String? _error;
String? get error => _error;

Future<void> selectRoom(RoomModel room) async {
  // ...
  try {
    final loaded = await SupabaseService.getMessages(room.id);
    // ...
    _error = null;
  } on AppException catch (e) {
    _error = e.message;
  } finally {
    _isLoading = false;
    notifyListeners();
  }
}
```

**En la UI:** mostrar `chatProvider.error` con un botón “Reintentar”. No mostrar “canal vacío” cuando hay error.

---

### 9.4. Historial y paginación (BUG-01)

**Servicio:** el snippet de 9.3 ya ordena descendente, limita y revierte. Añadir cursor por `created_at` + `id` para evitar duplicados con timestamps iguales:

```dart
static Future<List<MessageModel>> getMessagesBefore({
  required String roomId,
  required DateTime before,
  required String beforeId,
  int limit = 50,
}) async {
  final rows = await client
      .from('messages')
      .select('*, profiles(*), message_reactions(*)')
      .eq('room_id', roomId)
      .or('created_at.lt.${before.toUtc().toIso8601String()},'
          'and(created_at.eq.${before.toUtc().toIso8601String()},id.lt.$beforeId)')
      .order('created_at', ascending: false)
      .order('id', ascending: false)
      .limit(limit);

  return (rows as List)
      .map((m) => MessageModel.fromJson(m as Map<String, dynamic>))
      .toList()
      .reversed
      .toList();
}
```

**Provider:**

```dart
bool _hasMore = true;
bool _loadingMore = false;

Future<void> loadOlderMessages() async {
  if (_loadingMore || !_hasMore || _messages.isEmpty || _activeRoom == null) {
    return;
  }
  _loadingMore = true;
  notifyListeners();

  final first = _messages.first;
  try {
    final older = await SupabaseService.getMessagesBefore(
      roomId: _activeRoom!.id,
      before: first.createdAt,
      beforeId: first.id,
      limit: 50,
    );
    _hasMore = older.length == 50;
    _messages = [...older, ..._messages];
  } finally {
    _loadingMore = false;
    notifyListeners();
  }
}
```

**UI (`HomeScreen`):** escuchar el scroll y pedir más cerca del inicio, preservando la posición:

```dart
void _onScroll() {
  if (_scrollController.position.pixels < 200) {
    final before = _scrollController.position.maxScrollExtent;
    context.read<ChatProvider>().loadOlderMessages().then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final after = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(
          _scrollController.offset + (after - before),
        );
      });
    });
  }
}
```

> Alternativa más simple para la entrega: cargar los últimos 50 al abrir y no implementar scroll infinito todavía. Lo importante es **no** quedarse con los 100 más antiguos.

---

### 9.5. Race de salas, loading y Realtime (BUG-02/16/17)

```dart
int _roomRequest = 0;
Timer? _reloadDebounce;

Future<void> selectRoom(RoomModel room) async {
  final request = ++_roomRequest;

  _activeRoom = room;
  _messages = [];
  _typingStatusText = null;
  _isLoading = true;
  _error = null;
  notifyListeners();

  _cleanupSubscriptions();

  try {
    final loaded = await SupabaseService.getMessages(room.id);
    if (request != _roomRequest || _activeRoom?.id != room.id) return;

    _messages = loaded;
    _messagesSubscription = SupabaseService.subscribeToRoomMessages(
      roomId: room.id,
      onDataChanged: () => _scheduleReload(room.id, request),
    );
    _typingSubscription = SupabaseService.listenTypingStatus(
      roomId: room.id,
      onTyping: (userName, isTyping) {
        if (request != _roomRequest || _activeRoom?.id != room.id) return;
        // ...
      },
    );
  } on AppException catch (e) {
    if (request == _roomRequest) _error = e.message;
  } finally {
    if (request == _roomRequest) {
      _isLoading = false;
      notifyListeners();
    }
  }
}

void _scheduleReload(String roomId, int request) {
  _reloadDebounce?.cancel();
  _reloadDebounce = Timer(const Duration(milliseconds: 150), () async {
    if (request != _roomRequest || _activeRoom?.id != roomId) return;
    try {
      final loaded = await SupabaseService.getMessages(roomId);
      if (request != _roomRequest || _activeRoom?.id != roomId) return;
      _messages = loaded;
      _error = null;
      notifyListeners();
    } on AppException catch (e) {
      if (request == _roomRequest) {
        _error = e.message;
        notifyListeners();
      }
    }
  });
}
```

**Realtime filtrado:** añadir `room_id` a `message_reactions` y `message_reads` (sección 8.3) y usarlo en los filtros:

```dart
channel
    .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'messages',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (_) => onDataChanged(),
    )
    .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'message_reactions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (_) => onDataChanged(),
    )
    .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'message_reads',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (_) => onDataChanged(),
    )
    .subscribe();
```

> Si no se quiere denormalizar, la alternativa es actualizar el estado local con el payload del evento en lugar de refetchear, pero para reacciones necesitas saber a qué mensaje pertenecen; el `room_id` denormalizado es la solución más simple.

---

### 9.6. Presencia real (BUG-05)

**Opción A — lifecycle + heartbeat (mínima, sin Realtime Presence):**

```dart
class _PresenceController with WidgetsBindingObserver {
  Timer? _heartbeat;
  String? _uid;

  void start(String uid) {
    _uid = uid;
    WidgetsBinding.instance.addObserver(this);
    _setOnline(true);
    _heartbeat = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _setOnline(true),
    );
  }

  void _setOnline(bool online) {
    final uid = _uid;
    if (uid != null) SupabaseService.updatePresence(uid, online);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _setOnline(state == AppLifecycleState.resumed);
  }

  void dispose() {
    _heartbeat?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _setOnline(false);
  }
}
```

**Además:** suscribirse a `profiles` para refrescar `MembersSidebar`:

```dart
static RealtimeChannel subscribeToProfiles(void Function() onChanged) {
  final channel = client.channel('public:profiles');
  channel.onPostgresChanges(
    event: PostgresChangeEvent.all,
    schema: 'public',
    table: 'profiles',
    callback: (_) => onChanged(),
  ).subscribe();
  return channel;
}
```

En `ChatProvider`, guardar el canal y recargar perfiles con debounce. No confundir “en línea” con “última vez”: si usas solo `is_online`, un cierre abrupto deja el estado sucio; usa `last_seen` y considera offline si `now - last_seen > 2 min`.

**Opción B — Supabase Realtime Presence (recomendada para exactitud):**

```dart
final channel = client.channel(
  'presence:global',
  opts: const RealtimeChannelConfig(self: true),
);

channel
    .onPresenceSync((_) {
      final state = channel.presenceState();
      // state: Map<String, List<Presence>>
      // actualizar el provider con los user_id presentes
    })
    .onPresenceJoin((_) => /* refrescar */)
    .onPresenceLeave((_) => /* refrescar */);

await channel.subscribe((status, error) async {
  if (status == RealtimeSubscribeStatus.subscribed) {
    await channel.track({
      'user_id': _uid,
      'display_name': _name,
      'online_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
});
```

> Presence de Realtime requiere que el canal esté autorizado con el token (`realtime.setAuth`). Para la entrega, la opción A + `last_seen` es suficiente y menos riesgosa.

---

### 9.7. Typing con throttle y canal privado (BUG-09/SEC-09)

**`ChatInputBar`:**

```dart
Timer? _typingStop;
bool _typingSent = false;

void _onTextChanged(String value) {
  final provider = context.read<ChatProvider>();
  if (value.trim().isEmpty) {
    _typingStop?.cancel();
    if (_typingSent) {
      _typingSent = false;
      provider.notifyTyping(false);
    }
    return;
  }

  if (!_typingSent) {
    _typingSent = true;
    provider.notifyTyping(true);
  }

  _typingStop?.cancel();
  _typingStop = Timer(const Duration(seconds: 2), () {
    _typingSent = false;
    provider.notifyTyping(false);
  });
}

@override
void dispose() {
  _typingStop?.cancel();
  _controller.dispose();
  super.dispose();
}
```

**Canal privado:** `client.channel('typing:$roomId', opts: const RealtimeChannelConfig(private: true))`. Para que funcione, configura Realtime Authorization en Supabase y usa `realtime.setAuth`. Además, no confíes en `user_name` del payload: envía `user_id` y resuelve el nombre contra `profiles`, o muestra “Alguien está escribiendo…”.

---

### 9.8. Registro, perfil e inicialización (BUG-06/07/08)

**Opción recomendada — Cloud Function `onCreate` (Admin SDK):**

```ts
// functions/src/index.ts (Node.js, Firebase Functions v1 auth trigger)
import { auth } from 'firebase-functions/v1';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

export const onUserCreated = auth.user().onCreate(async (user) => {
  await getAuth().setCustomUserClaims(user.uid, { role: 'authenticated' });

  // Perfil en Supabase con service_role (variable de entorno del servidor)
  await fetch(`${process.env.SUPABASE_URL}/rest/v1/profiles`, {
    method: 'POST',
    headers: {
      apikey: process.env.SUPABASE_SERVICE_ROLE_KEY!,
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY!}`,
      'Content-Type': 'application/json',
      Prefer: 'resolution=merge-duplicates',
    },
    body: JSON.stringify({
      id: user.uid,
      display_name: user.displayName ?? user.email?.split('@')[0] ?? 'Usuario',
      bio: '¡Hola! Estoy usando Discord EPN.',
      is_online: false,
    }),
  });
});
```

> `onCreate` es asíncrono: el primer ID token puede no tener el claim. En el cliente, tras registrar, haz `await user.getIdToken(true)` antes de la primera consulta a Supabase. Para usuarios existentes, ejecuta un script con `getAuth().listUsers()` + `setCustomUserClaims(uid, { role: 'authenticated' })`.

**Cliente (registro):**

```dart
static Future<UserCredential> registerWithEmail({
  required String email,
  required String password,
  required String displayName,
}) async {
  final credential = await _auth.createUserWithEmailAndPassword(
    email: email,
    password: password,
  );

  final user = credential.user;
  if (user != null) {
    await user.updateDisplayName(displayName);
    await user.getIdToken(true); // fuerza el claim role
    await Supabase.instance.client.realtime.setAuth(await user.getIdToken());
  }

  return credential;
}
```

**Fallback si no hay Cloud Function:** en `loginWithEmail`, después de autenticar, comprobar `getProfile(uid)`; si es `null` y el JWT ya tiene `role=authenticated`, hacer `upsertProfile` con los datos de Firebase. Si el claim aún no está, mostrar un error claro y reintentar; **no** dejar la app en silencio.

**`ChatProvider.initializeUser`:**

```dart
Future<void> initializeUser(String userId) async {
  _isLoading = true;
  _error = null;
  notifyListeners();

  try {
    _currentUserProfile = await SupabaseService.getProfile(userId);
    if (_currentUserProfile == null) {
      throw const AppException(
        'Tu perfil no está creado. Vuelve a iniciar sesión o contacta al administrador.',
      );
    }

    await loadRooms();
    await loadProfiles();
    if (_rooms.isNotEmpty && _activeRoom == null) {
      await selectRoom(_rooms.first);
    }
  } on AppException catch (e) {
    _error = e.message;
  } catch (e) {
    _error = 'No se pudo inicializar el chat.';
  } finally {
    _isLoading = false;
    notifyListeners();
  }
}
```

**`AuthGate` como `StatefulWidget`:**

```dart
class _AuthGateState extends State<AuthGate> {
  String? _initializedFor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;
        if (user == null) {
          _initializedFor = null;
          return const LoginScreen();
        }

        if (_initializedFor != user.uid) {
          _initializedFor = user.uid;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            context.read<ChatProvider>().initializeUser(user.uid);
          });
        }

        return const HomeScreen();
      },
    );
  }
}
```

Si `initializeUser` falla, `HomeScreen` debe mostrar `chatProvider.error` y un botón que resetee `_initializedFor`/llame de nuevo. No vuelvas a llamar automáticamente en cada build.

---

### 9.9. FCM real (SEC-10/BUG-18)

Hoy solo se pide permiso y se imprime el token (`main.dart:28-45`). Para que las notificaciones existan:

1. **No guardes el token en `profiles`.** `profiles` es legible por cualquier usuario autenticado (`profiles_select_authenticated`); un `fcm_token` ahí queda expuesto a todos y permite enviar notificaciones no deseadas. Crear una tabla separada con RLS propia:

```sql
create table if not exists public.user_push_tokens (
  user_id text not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('android','ios','web')),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

alter table public.user_push_tokens enable row level security;

revoke all on public.user_push_tokens from anon;
grant select, insert, update, delete on public.user_push_tokens to authenticated, service_role;

create policy push_tokens_select_own
on public.user_push_tokens for select
to authenticated
using (user_id = public.current_firebase_uid());

create policy push_tokens_insert_own
on public.user_push_tokens for insert
to authenticated
with check (user_id = public.current_firebase_uid());

create policy push_tokens_update_own
on public.user_push_tokens for update
to authenticated
using (user_id = public.current_firebase_uid())
with check (user_id = public.current_firebase_uid());

create policy push_tokens_delete_own
on public.user_push_tokens for delete
to authenticated
using (user_id = public.current_firebase_uid());
```

> El servidor que envía las notificaciones usa `service_role`, que salta RLS. El cliente solo ve y modifica sus propios tokens.

2. Guardar el token tras login:

```dart
final messaging = FirebaseMessaging.instance;
await messaging.requestPermission(alert: true, badge: true, sound: true);
final token = await messaging.getToken(
  // En web: obtener la VAPID key en Firebase Console → Cloud Messaging → Web Push.
  vapidKey: kIsWeb ? const String.fromEnvironment('FCM_VAPID_KEY') : null,
);
if (token != null) {
  await SupabaseService.upsertPushToken(
    userId: uid,
    token: token,
    platform: kIsWeb
        ? 'web'
        : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'),
  );
}
```

**`SupabaseService.upsertPushToken`:**

```dart
static Future<void> upsertPushToken({
  required String userId,
  required String token,
  required String platform,
}) async {
  await client.from('user_push_tokens').upsert(
    {
      'user_id': userId,
      'token': token,
      'platform': platform,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
    onConflict: 'user_id,token',
  );
}
```

3. Manejar foreground/background:

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

// En main(), antes de runApp:
FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
FirebaseMessaging.onMessage.listen((message) {
  // Mostrar banner in-app o notificación local con flutter_local_notifications.
});
```

4. Enviar desde el servidor: una Edge Function de Supabase (o Cloud Function) escucha el `INSERT` en `messages` y envía FCM HTTP v1 a los tokens de `user_push_tokens` de los miembros de la sala, excluyendo al remitente. La **service account** de Firebase vive solo en el servidor; nunca en la app.
5. Web: crear `web/firebase-messaging-sw.js` con la configuración pública y registrar el service worker; sin esto, FCM web no funciona.
6. Eliminar `print('FCM Token registrado: $fcmToken')` o redactarlo; un token es una credencial de envío.

> Si no se va a implementar el envío en el servidor, es más honesto **quitar** la afirmación “Notificaciones Push 100%” del README/CHECKPOINT y dejar solo “permisos y token solicitados”.

---

### 9.10. Voz, MIME y subida de archivos (BUG-11/12)

**Regla:** el formato/extensión/MIME deben ser coherentes entre grabación, subida, base de datos y reproducción.

**Móvil (Android/iOS):** grabar a archivo con AAC (contenedor MP4/M4A correcto):

```dart
// Dependencia extra: path_provider
final dir = await getTemporaryDirectory();
final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

await _recorder.start(
  const RecordConfig(
    encoder: AudioEncoder.aacLc,
    bitRate: 64000,
    sampleRate: 44100,
    numChannels: 1,
  ),
  path: path,
);

// ...
final savedPath = await _recorder.stop();
if (savedPath != null) {
  final bytes = await File(savedPath).readAsBytes();
  widget.onSendAudio(bytes, extension: 'm4a', mimeType: 'audio/mp4');
}
```

**Web:** `record_web` **no soporta AAC en stream**; usar grabación a archivo con WAV (soportado) y leer el blob:

```dart
// Dependencia extra: http
if (kIsWeb) {
  await _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000,
      numChannels: 1,
    ),
    // En web `path` es obligatorio, aunque el blob se obtiene con stop().
    path: 'voice_${DateTime.now().millisecondsSinceEpoch}.wav',
  );

  final blobUrl = await _recorder.stop();
  if (blobUrl != null) {
    final response = await http.get(Uri.parse(blobUrl));
    widget.onSendAudio(
      response.bodyBytes,
      extension: 'wav',
      mimeType: 'audio/wav',
    );
  }
}
```

> Si se insiste en `startStream` en web, usar `AudioEncoder.pcm16bits` y envolver el PCM en un WAV con cabecera; no usar `aacLc`. En móvil, si se usa `startStream(AudioEncoder.aacLc)`, guardar como `.aac` y `audio/aac` (es ADTS), **no** como `.m4a`.

**Límites y UX:**

```dart
static const maxVoiceSeconds = 60;
static const maxVoiceBytes = 10 * 1024 * 1024;

Timer(const Duration(seconds: maxVoiceSeconds), () {
  if (_isRecording && mounted) _finishAndSend();
});
```

- Si `_audioChunks` supera `maxVoiceBytes`, detener y avisar.
- Mostrar el error **antes** de `Navigator.pop()` o devolverlo al padre; no usar `ScaffoldMessenger.of(context)` después de cerrar el diálogo.

**MIME de imágenes:** usar una allowlist, no `image/$ext`:

```dart
const _imageMime = <String, String>{
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
};

String? mimeForImage(String fileName) {
  final ext = fileName.split('.').last.toLowerCase();
  return _imageMime[ext];
}
```

**Sanitizar nombre, limitar tamaño y unificar MIME (`StorageService`):**

```dart
static const maxAvatarBytes = 5 * 1024 * 1024;
static const maxImageBytes = 10 * 1024 * 1024;
static const maxAudioBytes = 10 * 1024 * 1024;

static String _safeName(String name) =>
    name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

static void _checkSize(Uint8List bytes, int max, String label) {
  if (bytes.lengthInBytes > max) {
    throw AppException('$label supera el límite de ${max ~/ (1024 * 1024)} MB.');
  }
}
```

**`uploadAvatar` (MIME correcto, no `image/$extension`):**

```dart
static Future<String> uploadAvatar({
  required String userId,
  required Uint8List bytes,
  required String extension,
}) async {
  final ext = extension.toLowerCase();
  final normalized = ext == 'jpeg' ? 'jpg' : ext;
  final mime = _imageMime[normalized];
  if (mime == null) {
    throw const AppException('Formato de avatar no permitido.');
  }
  _checkSize(bytes, maxAvatarBytes, 'El avatar');

  final ref = _storage.ref().child('avatars/$userId.$normalized');
  final snapshot = await ref.putData(
    bytes,
    SettableMetadata(contentType: mime),
  );
  return snapshot.ref.getDownloadURL();
}
```

**`uploadVoiceNote` (extensión y MIME explícitos):**

```dart
static const _audioMime = <String, String>{
  'm4a': 'audio/mp4',
  'aac': 'audio/aac', // ADTS
  'wav': 'audio/wav',
  'webm': 'audio/webm',
  'ogg': 'audio/ogg',
  'mp3': 'audio/mpeg',
};

static Future<String> uploadVoiceNote({
  required String roomId,
  required Uint8List audioBytes,
  required String extension,
  required String mimeType,
}) async {
  final ext = extension.toLowerCase();
  if (_audioMime[ext] != mimeType) {
    throw const AppException('Formato de audio no permitido.');
  }
  _checkSize(audioBytes, maxAudioBytes, 'La nota de voz');

  final id =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
  final ref = _storage.ref().child('voice_notes/$roomId/$id.$ext');
  final snapshot = await ref.putData(
    audioBytes,
    SettableMetadata(contentType: mimeType),
  );
  return snapshot.ref.getDownloadURL();
}
```

**`uploadChatMedia` (nombre saneado y tamaño máximo):**

```dart
static Future<String> uploadChatMedia({
  required String roomId,
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  _checkSize(bytes, maxImageBytes, 'El archivo');
  final id =
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
  final ref = _storage.ref().child(
    'chat_media/$roomId/${id}_${_safeName(fileName)}',
  );
  final snapshot = await ref.putData(
    bytes,
    SettableMetadata(contentType: mimeType),
  );
  return snapshot.ref.getDownloadURL();
}
```

**Regla de base de datos:** `messages_media_required` y `messages_type_allowed` (sección 8.4) evitan filas incoherentes aunque el cliente falle.

---

### 9.11. Auto-scroll respetando al usuario (BUG-03)

```dart
bool _wasNearBottom = true;
int _lastMessageCount = 0;

bool get _isNearBottom {
  if (!_scrollController.hasClients) return true;
  final p = _scrollController.position;
  return p.maxScrollExtent - p.pixels < 120;
}

@override
Widget build(BuildContext context) {
  final messages = context.watch<ChatProvider>().messages;

  // Capturar antes de que el nuevo layout cambie maxScrollExtent.
  _wasNearBottom = _isNearBottom;
  final grew = messages.length > _lastMessageCount;
  final isInitialLoad = _lastMessageCount == 0 && messages.isNotEmpty;
  _lastMessageCount = messages.length;

  if (grew || isInitialLoad) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_wasNearBottom || isInitialLoad) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ... resto del build
}
```

Así, si el usuario está leyendo arriba, un mensaje nuevo no lo arrastra. Opcional: mostrar un botón “Ir al final” cuando `_isNearBottom == false`.

---

### 9.12. Cerrar el drawer correctamente (BUG-04)

**En `ChannelSidebar`:**

```dart
onTap: () {
  chatProvider.selectRoom(room);
  Scaffold.maybeOf(context)?.closeDrawer();
},
```

**Alternativa robusta:** `HomeScreen` pasa un callback `onRoomSelected` que hace `_scaffoldKey.currentState?.closeDrawer()` y `selectRoom`. Evita depender del `Navigator` y de `canPop()`.

Para el `endDrawer`, igual: `Scaffold.maybeOf(context)?.closeEndDrawer()`.

---

### 9.13. Reacciones atómicas (BUG-10)

**Cliente:**

```dart
static Future<bool> toggleReaction({
  required String messageId,
  required String reaction,
}) async {
  final added = await client.rpc(
    'toggle_reaction',
    params: {
      'p_message_id': messageId,
      'p_reaction': reaction,
    },
  );
  return added as bool;
}
```

**Provider:**

```dart
Future<void> toggleReaction(String messageId, String emoji) async {
  try {
    await SupabaseService.toggleReaction(
      messageId: messageId,
      reaction: emoji,
    );
    await _reloadReactionsFor(messageId);
  } on AppException catch (e) {
    _error = e.message;
    notifyListeners();
  }
}
```

`_reloadReactionsFor` puede hacer una consulta pequeña:

```dart
final rows = await SupabaseService.client
    .from('message_reactions')
    .select()
    .eq('message_id', messageId);
```

Actualizar solo ese mensaje en `_messages` con `copyWith(reactions: ...)`, no toda la lista. Si se prefiere optimista, agregar/quitar en local y revertir si el RPC falla.

---

### 9.14. Diálogo de perfil sin overflow y avatar diferido (BUG-13)

```dart
return Dialog(
  insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
  backgroundColor: DiscordColors.channelSidebar,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  child: ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: 440,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
    ),
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ... contenido actual
        ],
      ),
    ),
  ),
);
```

**Avatar diferido:**

```dart
Uint8List? _pendingAvatar;
String? _pendingAvatarExt;

Future<void> _pickAvatar() async {
  final image = await _picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 512,
    maxHeight: 512,
    imageQuality: 85,
  );
  if (image == null) return;

  final ext = image.name.split('.').last.toLowerCase();
  if (!const ['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
    // mostrar error
    return;
  }

  final bytes = await image.readAsBytes();
  if (!mounted) return;
  setState(() {
    _pendingAvatar = bytes;
    _pendingAvatarExt = ext;
  });
}
```

**Guardar sin usar `context` después de `pop`:**

```dart
Future<void> _saveProfile() async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  final name = _nameController.text.trim();
  if (name.isEmpty) return;

  setState(() => _isSaving = true);
  try {
    await context.read<ChatProvider>().updateProfile(
      displayName: name,
      bio: _bioController.text.trim(),
      newAvatarBytes: _pendingAvatar,
      avatarExtension: _pendingAvatarExt,
    );

    if (!mounted) return;
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(
        backgroundColor: DiscordColors.green,
        content: Text('Perfil actualizado con éxito'),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: DiscordColors.red,
        content: Text('Error al guardar perfil: $e'),
      ),
    );
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}
```

> `_pendingAvatar` se lee una sola vez al guardar. Si el usuario cancela el diálogo, no se sube nada. Captura `ScaffoldMessenger`/`Navigator` **antes** del `await`: después de `pop()` el `context` del diálogo queda desmontado y `ScaffoldMessenger.of(context)` puede fallar o no mostrar el mensaje.

También validar `displayName` (3-32) y `bio` (≤190) en el cliente antes de guardar.

---

### 9.15. Un solo audio a la vez y listeners cancelados (BUG-14)

**Opción simple:** `ValueNotifier<String?> playingMessageId` en `HomeScreen`/provider. Cada `_VoicePlayerWidget` recibe `isPlaying` y `onPlay`; al reproducir uno, se pausa el anterior.

**Opción con `AudioPlayer` compartido:** crear un `AudioPlayer` en el provider y exponer `play(url, messageId)`, `pause()`, `stop()`. Las burbujas solo dibujan el estado.

**Cancelar listeners:**

```dart
StreamSubscription<PlayerState>? _stateSub;
StreamSubscription<Duration>? _durationSub;
StreamSubscription<Duration>? _positionSub;

@override
void initState() {
  super.initState();
  _stateSub = _player.onPlayerStateChanged.listen((state) {
    if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
  });
  _durationSub = _player.onDurationChanged.listen((d) {
    if (mounted) setState(() => _duration = d);
  });
  _positionSub = _player.onPositionChanged.listen((p) {
    if (mounted) setState(() => _position = p);
  });
}

@override
void dispose() {
  _stateSub?.cancel();
  _durationSub?.cancel();
  _positionSub?.cancel();
  _player.dispose();
  super.dispose();
}
```

Además, `await _player.setReleaseMode(ReleaseMode.stop);` para que al terminar no quede el estado “playing”.

---

### 9.16. Crear salas con owner y validación (BUG-15)

**Cliente:**

```dart
static Future<RoomModel> createRoom(String name) async {
  final clean = name.trim();
  if (clean.isEmpty) {
    throw const AppException('El nombre del canal no puede estar vacío.');
  }

  try {
    final response = await client.rpc(
      'create_room',
      params: {'p_name': clean},
    );
    return RoomModel.fromJson(response as Map<String, dynamic>);
  } on PostgrestException catch (e) {
    if (e.code == '23505') {
      throw const AppException('Ya existe un canal con ese nombre.');
    }
    if (e.code == '22023') {
      throw const AppException(
        'Nombre inválido. Usa 2-32 caracteres: letras, números y guiones.',
      );
    }
    rethrow;
  }
}
```

**Provider:** no hagas `_rooms.add(newRoom)` a mano si el Realtime de `rooms` no está suscrito; recarga `loadRooms()` después de crear, o mantén el `add` pero sin duplicar si ya existe.

**Trigger:** `add_room_owner` (sección 8.5) inserta la membresía `owner` automáticamente. Verifica que la política `members_insert_owner` no bloquee el trigger: el trigger es `SECURITY DEFINER`, así que inserta con los privilegios del owner de la función (postgres), saltando RLS. Es intencional; revisa que la función no sea invocable por `anon`.

---

### 9.17. Arranque con validación y pantalla de error (BUG-19)

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // logger.crash(details.exception, details.stack);
  };

  ErrorWidget.builder = (details) => const _StartupErrorScreen(
    message: 'Ocurrió un error inesperado.',
  );

  try {
    AppConfig.validate();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await SupabaseService.initialize();
    runApp(/* ... */);
  } catch (e, st) {
    // logger.crash(e, st);
    runApp(_StartupErrorScreen(message: 'No se pudo iniciar la app: $e'));
  }
}
```

`_StartupErrorScreen` debe ser un `MaterialApp` mínimo con el mensaje y un botón “Reintentar” (o instrucciones para el administrador). No dejes una pantalla en blanco.

---

### 9.18. No perder el texto si el envío falla (BUG-22)

```dart
Future<void> _handleSendText() async {
  final text = _controller.text.trim();
  if (text.isEmpty || _isSending) return;

  setState(() => _isSending = true);
  context.read<ChatProvider>().notifyTyping(false);

  try {
    await context.read<ChatProvider>().sendTextMessage(text);
    if (!mounted) return;
    // Limpiar solo cuando el envío se confirmó.
    _controller.clear();
  } catch (e) {
    if (!mounted) return;
    // El texto sigue en el campo: no se pierde.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: DiscordColors.red,
        content: Text('No se pudo enviar: $e'),
      ),
    );
  } finally {
    if (mounted) setState(() => _isSending = false);
  }
}
```

Si se prefiere limpiar de inmediato para permitir escribir otro mensaje, guardar `text` y restaurarlo solo si el envío falla **y** el usuario no cambió el campo (`_controller.text.isEmpty`). No limpiar si el provider lanzó una excepción.

---

## 10. Storage, Hosting y hardening

### 10.1. `storage.rules`

Crear en la raíz:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    function signedIn() {
      return request.auth != null;
    }

    function isImage() {
      return request.resource.contentType.matches('image/.*');
    }

    function isAudio() {
      return request.resource.contentType.matches('audio/.*');
    }

    // Avatares: solo el dueño escribe; lectura pública (URL bearer de todos modos)
    match /avatars/{userId}.{ext} {
      allow read: if true;
      allow write: if signedIn()
        && request.auth.uid == userId
        && request.resource.size < 5 * 1024 * 1024
        && isImage();
    }

    // Imágenes del chat
    match /chat_media/{roomId}/{fileName} {
      allow read: if signedIn();
      allow write: if signedIn()
        && request.resource.size < 10 * 1024 * 1024
        && isImage()
        && fileName.matches('.*\\.(jpg|jpeg|png|webp|gif)$');
    }

    // Notas de voz
    match /voice_notes/{roomId}/{fileName} {
      allow read: if signedIn();
      allow write: if signedIn()
        && request.resource.size < 10 * 1024 * 1024
        && isAudio()
        && fileName.matches('.*\\.(m4a|aac|wav|webm|ogg|mp3)$');
    }

    // Bloquear todo lo demás
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

**Limitación importante:** estas reglas no pueden comprobar si el usuario pertenece a `roomId` en Supabase. Para aislamiento real:

- Opción A (simple): aceptar que cualquier usuario autenticado con la URL pueda leer el archivo; proteger la URL dentro de mensajes con RLS.
- Opción B (estricta): subir mediante una Edge Function que valide la sala con `service_role`, genere una **signed upload URL** y guarde el archivo en un bucket privado; para descargar, generar signed download URLs de corta duración. Esto elimina el problema de las URLs bearer.

**Probar reglas:** usar `@firebase/rules-unit-testing` con el emulador de Storage (sección 11).

### 10.2. `firebase.json` y `.firebaserc`

`firebase.json`:

```json
{
  "hosting": {
    "public": "build/web",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      { "source": "**", "destination": "/index.html" }
    ],
    "headers": [
      {
        "source": "**",
        "headers": [
          { "key": "X-Content-Type-Options", "value": "nosniff" },
          { "key": "X-Frame-Options", "value": "DENY" },
          { "key": "Referrer-Policy", "value": "strict-origin-when-cross-origin" },
          { "key": "Permissions-Policy", "value": "camera=(), microphone=(self), geolocation=(self)" },
          { "key": "Strict-Transport-Security", "value": "max-age=31536000; includeSubDomains" }
        ]
      }
    ]
  },
  "storage": {
    "rules": "storage.rules"
  }
}
```

> **CSP:** Flutter web + Supabase + Firebase necesita permisos para `connect-src` a `https://*.supabase.co`, `wss://*.supabase.co`, `https://*.googleapis.com`, `https://firebasestorage.googleapis.com`, `https://securetoken.googleapis.com`, `https://identitytoolkit.googleapis.com`, y para CanvasKit `https://www.gstatic.com`. Si se añade CSP, probarla en local y en el deploy; un CSP demasiado estricto deja la web en blanco. No la agregues a ciegas.

`.firebaserc`:

```json
{
  "projects": {
    "default": "tu-firebase-project-id"
  }
}
```

Desplegar:

```powershell
firebase deploy --only hosting,storage
```

### 10.3. Android release y backups

`android/app/build.gradle.kts`:

```kotlin
import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    // ...
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}
```

`android/key.properties` (ignorado por git; ya está `android/key.properties` en `.gitignore`):

```properties
storePassword=...
keyPassword=...
keyAlias=...
storeFile=C:/ruta/segura/discord-epn-release.jks
```

`AndroidManifest.xml`:

```xml
<application
    android:label="Discord EPN"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher"
    android:allowBackup="false"
    android:fullBackupContent="false"
    android:dataExtractionRules="@xml/data_extraction_rules"
    android:usesCleartextTraffic="false">
```

Crear `android/app/src/main/res/xml/data_extraction_rules.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="sharedpref" path="."/>
        <exclude domain="database" path="."/>
        <exclude domain="file" path="."/>
    </cloud-backup>
    <device-transfer>
        <exclude domain="sharedpref" path="."/>
        <exclude domain="database" path="."/>
        <exclude domain="file" path="."/>
    </device-transfer>
</data-extraction-rules>
```

Verificar:

```powershell
apksigner verify --print-certs build\app\outputs\flutter-apk\app-release.apk
```

La huella debe ser la del keystore de release, no la de debug.

### 10.4. Web: manifest, index y FCM

`web/manifest.json`:

```json
{
  "name": "Discord EPN",
  "short_name": "Discord EPN",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#1E1F22",
  "theme_color": "#5865F2",
  "description": "Chat en tiempo real de la comunidad EPN.",
  "orientation": "portrait-primary",
  "prefer_related_applications": false,
  "icons": [
    { "src": "icons/Icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icons/Icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "icons/Icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icons/Icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

`web/index.html`: cambiar `<meta name="description">` y `<title>` a “Discord EPN”. Si se implementa FCM web, añadir `web/firebase-messaging-sw.js` con la configuración pública y el handler `onBackgroundMessage`; sin ese archivo, las notificaciones web no llegan.

### 10.5. Cabeceras y CORS

- No hace falta configurar CORS en Supabase para el cliente Flutter; Supabase ya lo permite.
- Si se usa una Edge Function para FCM/signed URLs, restringir CORS a los dominios de Hosting (`https://tu-proyecto.web.app`, `https://tu-proyecto.firebaseapp.com`), no `*`.
- No exponer `SUPABASE_SERVICE_ROLE_KEY` en el cliente ni en `--dart-define`. Solo en el servidor (Edge Function/Cloud Function).

---

## 11. Pruebas que se deben añadir

### 11.1. Unitarias de modelos (ya existen; ampliar)

- `MessageModel.fromJson` con `profiles` nulo, `message_reactions` nulo, `created_at` inválido.
- `RoomModel.fromJson` con `name` nulo.
- `UserProfile.copyWith` no permite limpiar `avatarUrl` (si se necesita, añadir un `clearAvatar`).

### 11.2. Provider (con repositorio falso)

Refactorizar `ChatProvider` para recibir una interfaz (por ejemplo `ChatRepository`) en el constructor; hoy usa estáticos, lo que impide testear. Casos:

1. `selectRoom(A)` y `selectRoom(B)` con respuestas fuera de orden → `_messages` debe ser de B.
2. Error de `getMessages` → `_isLoading=false`, `error != null`, no se muestra “vacío”.
3. `sendTextMessage('   ')` → no llama al repositorio.
4. `sendTextMessage` sin perfil → error visible, no silencio.
5. `initializeUser` con `getProfile` null → error, no loop.
6. `loadOlderMessages` no duplica mensajes y preserva orden.
7. `toggleReaction` llama al RPC una vez.
8. `dispose` cancela timers/suscripciones (usar `fakeAsync`).

### 11.3. Widgets

- `ChatInputBar`: enviar vacío no llama; enviar texto limpia el campo **solo si el envío tuvo éxito**; si `sendTextMessage` lanza, el texto permanece y aparece SnackBar; se envía `notifyTyping(false)` al enviar.
- `ProfileDialog`: con teclado simulado (`viewInsets`) no hay overflow; cancelar no sube avatar; nombre vacío no guarda.
- `ChannelSidebar`: tap en canal cierra el drawer (`ScaffoldState.isDrawerOpen == false`).
- `MessageBubble`: audio play/pause; solo un audio a la vez (si se implementa el coordinador).
- `HomeScreen`: auto-scroll solo si estaba cerca del fondo.

### 11.4. Integración / RLS (script)

Con dos usuarios de Firebase (A y B) y un usuario `anon`:

| Caso | Esperado |
| :--- | :--- |
| `anon` lee `rooms` | `401/403` o `[]` (según política), nunca datos |
| `anon` inserta `messages` | `401/403` |
| A lee `messages` de sala pública | OK |
| A inserta `sender_id = B` | `403` (WITH CHECK) |
| A actualiza mensaje de B | `0 filas` / `403` |
| A borra mensaje de B | `0 filas` / `403` |
| A lee sala privada sin membresía | `[]` |
| A inserta reacción con `user_id = B` | `403` |
| A lee `message_reads` de B | Solo lo permitido por política |
| A crea sala | Se crea y A queda `owner` en `room_members` |
| A crea sala duplicada | `23505` (unique) |

Automatizar con un script (Node/Dart) que obtenga ID tokens de Firebase y haga `fetch` a PostgREST. No usar la `service_role` en el cliente de prueba.

### 11.5. Storage rules

Con `@firebase/rules-unit-testing`:

- Usuario autenticado sube imagen < 10 MB a `chat_media/...` → permitido.
- Sube `.exe` con `image/png` falso → denegado por extensión/contenido (según regla).
- Sube 11 MB → denegado.
- Usuario A escribe en `avatars/B.jpg` → denegado.
- `anon` escribe → denegado.

### 11.6. Humo manual

- Registro nuevo → perfil creado, claim `authenticated`, puede enviar.
- Cerrar y abrir la app → sesión persiste, presencia correcta.
- Matar la app → `last_seen` se actualiza y el miembro pasa a offline (con heartbeat/lifecycle).
- Cambiar de canal rápido 10 veces → no se mezclan mensajes.
- Enviar 150 mensajes → al abrir se ven los últimos, scroll hacia arriba carga más.
- Grabar audio en Android y web → se reproduce en ambos.
- Subir imagen JPG/PNG/WebP → se ve; HEIC → mensaje de error claro.
- Cancelar edición de perfil tras elegir avatar → el avatar no cambia.
- Intentar acceder a una sala privada con otro usuario → no se ven mensajes.

---

## 12. Checklist de verificación

### 12.1. Antes de tocar nada

```powershell
git status
git log --oneline -3
flutter analyze
flutter test
```

- [ ] `git status` limpio o solo cambios esperados.
- [ ] `flutter analyze` sin issues.
- [ ] `flutter test` 7/7.
- [ ] Backup de Supabase hecho.
- [ ] `.env` y `google-services.json` no trackeados.

### 12.2. Después de la Fase 1 (auth bridge)

- [ ] El JWT de Firebase contiene `role: authenticated`.
- [ ] `auth.jwt() ->> 'sub'` devuelve el UID de Firebase.
- [ ] Una consulta autenticada a `rooms` funciona.
- [ ] `realtime.setAuth` se llama en login/registro/refresh/logout.
- [ ] `anon` sigue pudiendo leer (todavía no hay RLS) — se espera en esta fase.

### 12.3. Después de la Fase 2 (RLS)

- [ ] `rowsecurity = true` en las 6 tablas principales (y en `user_push_tokens` si se implementa FCM).
- [ ] `anon` no tiene grants ni acceso.
- [ ] Usuario A no puede insertar `sender_id` de B.
- [ ] Usuario A no puede actualizar/borrar mensajes de B.
- [ ] Usuario A no ve salas privadas ajenas.
- [ ] `create_room` deja owner en `room_members`.
- [ ] Realtime entrega mensajes solo de la sala activa.
- [ ] La app no muestra “vacío” cuando en realidad hay un error de permisos.

### 12.4. Después de la Fase 3 (bugs)

- [ ] Abrir un canal con >100 mensajes muestra los últimos, no los primeros.
- [ ] Cambiar de canal rápido no mezcla mensajes.
- [ ] El auto-scroll no interrumpe la lectura.
- [ ] El drawer se cierra al elegir canal.
- [ ] Un registro nuevo siempre tiene perfil.
- [ ] `AuthGate` no repite `initializeUser` en bucle.
- [ ] La presencia cambia al minimizar/volver y al cerrar sesión.
- [ ] Typing no envía un evento por tecla.
- [ ] Reacciones no fallan al doble tap.
- [ ] Audio móvil/web se graba, sube y reproduce.
- [ ] Perfil no desborda con teclado.
- [ ] Solo suena un audio a la vez.
- [ ] Si falla el envío de un mensaje, el texto permanece en el campo.

### 12.5. Después de la Fase 4 (Storage/Hosting)

- [ ] `storage.rules` desplegadas y probadas.
- [ ] `firebase.json` con headers/rewrites.
- [ ] `build/web/assets/.env` no existe.
- [ ] `flutter build web --release` compila.
- [ ] `flutter build apk --release` compila.
- [ ] `firebase deploy --only hosting,storage` funciona.
- [ ] La web carga y no hay errores de CSP en consola.

### 12.6. Release

- [ ] APK firmado con keystore de release.
- [ ] `apksigner verify --print-certs` muestra la huella correcta.
- [ ] `allowBackup=false`.
- [ ] `usesCleartextTraffic=false`.
- [ ] `--obfuscate --split-debug-info` usado.
- [ ] `google-services.json` presente solo en local/CI, nunca en git.

---

## 13. Evidencia de la auditoría

### 13.1. Comandos ejecutados

```powershell
flutter analyze
flutter test
```

Resultado: `No issues found!` y `7/7 All tests passed!`.

Verificación del `.env` en el build web:

```powershell
Get-Item build/web/assets/.env | Select-Object FullName, Length
Select-String -Path build/web/assets/AssetManifest.json -Pattern '\.env'
```

Resultado: el archivo existe (410 bytes) y está listado en el manifest.

Verificación de git:

```powershell
git ls-files | Select-String -Pattern '^\.env$|google-services\.json'
git log --all -- .env
```

Resultado: `.env` no está trackeado y no aparece en el historial; `google-services.json` está ignorado por `.gitignore:17`.

### 13.2. Pruebas contra Supabase (solo lectura / escrituras fallidas)

Se usó la publishable key del `.env` (no se reproduce aquí) contra el endpoint REST del proyecto. No se creó, modificó ni borró ningún dato; los `POST`/`PATCH` fueron con datos inválidos o no-op para observar el código de error.

| Operación | Resultado observado | Conclusión |
| :--- | :--- | :--- |
| `GET /rest/v1/rooms?select=name` | `200` con el canal existente | `anon` lee |
| `POST /rest/v1/messages` con FK inválida | Error FK | `anon` llega al SQL |
| `POST /rest/v1/rooms` con `name:null` | Error not-null | `anon` inserta |
| `POST /rest/v1/profiles` con `id:null` | Error not-null | `anon` inserta |
| `PATCH /rest/v1/rooms?id=eq.<uuid>` no-op | `204` | `anon` actualiza |

**Nota metodológica:** no se intentó borrar ni alterar datos reales; las pruebas se limitaron a lo mínimo para confirmar la ausencia de RLS. Cualquier prueba de penetración adicional debe hacerse en un proyecto de staging.

### 13.3. Limitaciones de la auditoría

- No se ejecutó un pentest completo ni se probaron todos los endpoints de Supabase Storage/Realtime con tokens de Firebase (el puente aún no existe).
- No se verificaron las reglas de Storage reales del proyecto (no están versionadas en el repo); se asume el riesgo por ausencia de `storage.rules`.
- No se probó en iOS ni en navegadores distintos de Chromium.
- No se revisó el contenido de `build/` más allá de la evidencia del `.env`; el build es un artefacto y no debe commitearse.
- Las claves del `.env` no se imprimieron ni se incluyeron en este documento.

---

## 14. Referencias internas

| Tema | Archivo:línea |
| :--- | :--- |
| Init Supabase sin auth | `lib/core/services/supabase_service.dart:11-19` |
| Perfil silencioso | `lib/core/services/supabase_service.dart:22-34` |
| Presencia | `lib/core/services/supabase_service.dart:40-47` |
| Rooms sin owner | `lib/core/services/supabase_service.dart:62-82` |
| Historial truncado | `lib/core/services/supabase_service.dart:85-98` |
| Envío sin validación | `lib/core/services/supabase_service.dart:100-118` |
| Realtime sin filtro de reacciones | `lib/core/services/supabase_service.dart:121-148` |
| Toggle no atómico | `lib/core/services/supabase_service.dart:151-180` |
| Read receipts sin usar | `lib/core/services/supabase_service.dart:183-194` |
| Typing spoofable | `lib/core/services/supabase_service.dart:197-229` |
| Race/loading | `lib/core/providers/chat_provider.dart:33-104` |
| Envíos silenciosos | `lib/core/providers/chat_provider.dart:116-198` |
| Registro no atómico | `lib/core/services/auth_service.dart:11-37` |
| Presencia login/logout | `lib/core/services/auth_service.dart:39-62` |
| FCM solo token | `lib/main.dart:28-45` |
| AuthGate re-init | `lib/main.dart:86-121` |
| Storage sin límites | `lib/core/services/storage_service.dart:8-52` |
| Envío imagen/MIME | `lib/ui/chat/widgets/chat_input_bar.dart:45-74` |
| Pérdida de texto al fallar envío | `lib/ui/chat/widgets/chat_input_bar.dart:27-43` |
| Typing por tecla | `lib/ui/chat/widgets/chat_input_bar.dart:222-224` |
| Voz AAC stream | `lib/ui/chat/widgets/voice_record_dialog.dart:33-87` |
| Audio múltiple | `lib/ui/chat/widgets/message_bubble.dart:309-360` |
| Drawer | `lib/ui/chat/widgets/channel_sidebar.dart:89-95` |
| Auto-scroll | `lib/ui/home/home_screen.dart:43-48` |
| Perfil overflow | `lib/ui/profile/profile_dialog.dart:110-290` |
| `.env` asset | `pubspec.yaml:73-74` |
| Debug signing | `android/app/build.gradle.kts:33-39` |
| Manifest backups | `android/app/src/main/AndroidManifest.xml:8-11` |
| Manifest web | `web/manifest.json:2-9` |
| DDL sin RLS | `PLAN_PROYECTO_DISCORD_EPN.md:121-180` |
| Promesas | `README.md:41-55`; `CHECKPOINT_PROYECTO.md:31-47` |

---

## 15. Anexo: checklist mínima para la entrega

- [ ] Auth bridge Firebase → Supabase funcionando y verificado.
- [ ] RLS activo en `profiles`, `rooms`, `room_members`, `messages`, `message_reactions`, `message_reads`.
- [ ] `storage.rules` y `firebase.json` versionados y desplegados.
- [ ] `.env` fuera del bundle; build web reconstruido.
- [ ] APK release firmado con keystore propio.
- [ ] Historial paginado y race de salas corregido.
- [ ] Registro/perfil atómico y `AuthGate` sin bucle.
- [ ] Presencia y typing con lifecycle/throttle.
- [ ] Voz funcionando en Android y web con formato/MIME correctos.
- [ ] `flutter analyze` y `flutter test` pasan.
- [ ] Tests nuevos de provider, RLS y Storage.
- [ ] README/CHECKPOINT actualizados para reflejar lo que realmente está implementado.
- [ ] Si falla un envío, el texto no se pierde; `user_push_tokens` (si existe) no es legible por otros usuarios.

> **Si solo hay tiempo para tres cambios:** (1) auth bridge + RLS, (2) historial/race de salas, (3) `.env` fuera del bundle + reglas de Storage. Son los de mayor impacto y menor ambigüedad.
