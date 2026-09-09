# Kalorias: registro con Apple después del onboarding local

**Para**: equipo de backend

**Feature**: `010-apple-auth-onboarding`

**Fecha**: 2026-09-08

**Cliente**: app iOS nativa, bundle/client id `com.quispe.kalorias.Kalorias`

Este documento es el handoff autocontenido de los **cambios de backend de la feature 010**. Da por
implementada la validación del cuestionario dinámico del paquete de onboarding; más abajo repite el
formato de envío y las reglas que cambian. Si contradice al brief anterior, este documento manda en
autenticación, propiedad de los datos y momento del envío.

## 1. Regla de producto que la API debe hacer cumplir

El usuario contesta todo el onboarding antes de crear una cuenta. Hasta que el registro termina,
las respuestas solo existen en el dispositivo. Registro y envío son dos peticiones distintas:

```text
iOS                         Backend Kalorias                   Apple
 |                                 |                              |
 | GET /onboarding (público)       |                              |
 |<--------------------------------|                              |
 | responde en local; no sube nada |                              |
 |                                 |                              |
 | autorización nativa con Apple -------------------------------->|
 |<---------------- identityToken + código de un solo uso --------|
 |                                 |                              |
 | POST /auth/apple                |                              |
 | (solo credenciales Apple)       | verificar token/canjear code |
 |                                 |----------------------------->|
 |                                 |<-----------------------------|
 |                                 | crear/leer usuario y sesión  |
 |<-- 200/201 usuario + sesión ----|                              |
 |                                 |                              |
 | consentimiento separado para tratar datos de salud             |
 |                                 |                              |
 | POST /kalorias/onboarding       |                              |
 | Bearer + respuestas pendientes  | validar + crear plan         |
 |<-- 200 confirmado/idempotente --|                              |
```

`/auth/apple` NO DEBE aceptar un objeto de onboarding. Una respuesta correcta de ese endpoint
significa que el usuario y una sesión renovable de Kalorias ya están confirmados en base de datos.
Solo después puede iOS enviar el payload de salud/perfil.

`GET /api/v1/kalorias/onboarding` sigue siendo público porque devuelve contenido, no datos del
usuario. `POST /api/v1/kalorias/onboarding` pasa a estar autenticado.

## 2. Cambios sobre los contratos existentes

| Comportamiento anterior | Comportamiento nuevo |
|---|---|
| `GET /api/v1/kalorias/onboarding` sin auth | **Sin cambios**: público y cacheable |
| `POST /api/v1/kalorias/onboarding` sin auth | **Sustituido**: requiere bearer de Kalorias |
| `POST /api/v1/kalorias/analyzeMeal` sin auth | **Sustituido**: requiere bearer de Kalorias |
| Idempotencia del onboarding sin usuario | Clave acotada por `(user_id, ruta, sessionId)` |
| Límite de análisis principalmente por IP | Límite de producto por usuario; techo antiabuso adicional por IP si hace falta |

El middleware de autenticación se ejecuta antes de leer/procesar el JSON del onboarding o la foto.
Una petición anónima a `analyzeMeal` no puede llamar al proveedor de IA. Esto también vuelve seguro
el único reintento del cliente tras renovar el access token: un `401` garantiza que el trabajo de
dominio no empezó.

Se conserva `X-Request-Id` en todas las respuestas, tanto correctas como fallidas.

## 3. Configuración en Apple Developer y secretos

Configuración necesaria solo en servidor:

```text
APPLE_TEAM_ID=<id del equipo de Apple Developer>
APPLE_CLIENT_ID=com.quispe.kalorias.Kalorias
APPLE_KEY_ID=<id de la clave Sign in with Apple>
APPLE_PRIVATE_KEY=<contenido/referencia a la clave .p8 en el gestor de secretos>
KALORIAS_ACCESS_TOKEN_SIGNING_KEY=<referencia a la clave de firma propia>
```

Requisitos:

1. Activar Sign in with Apple para el App ID. Configurarlo como App ID primario salvo que deba
   agruparse con una familia de apps que ya exista.
2. Crear una private key de Sign in with Apple para las llamadas del servidor. El `.p8`, el Apple
   `client_secret` generado y las claves de Kalorias viven únicamente en el gestor de secretos:
   nunca en el repositorio, xcconfig, app iOS o logs.
3. Generar el Apple `client_secret` en servidor, con una vida operativa corta y rotación previa a
   su caducidad. No pegar un JWT generado de larga duración en código o configuración plana.
4. Este flujo nativo iOS no necesita un Services ID ni redirect web. Si más adelante existe cliente
   web/Android, registrar su Services ID, dominio y redirect sin reutilizar supuestos de iOS.
5. Configurar en el App ID primario una URL de notificaciones server-to-server. La sección 11
   define el procesamiento requerido antes de producción.

Documentación oficial de Apple:

- [Configurar Sign in with Apple en Xcode](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple)
- [Verificar al usuario y obtener refresh token](https://developer.apple.com/documentation/signinwithapple/verifying-a-user)
- [Endpoint de validación/canje de tokens](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens)
- [Borrado de cuenta y revocación](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple)

Endpoints de Sign in with Apple que usa el servidor (no confundir con los endpoints distintos de
Account & Organizational Data Sharing):

| Operación | Endpoint |
|---|---|
| Claves públicas | `GET https://appleid.apple.com/auth/keys` |
| Canje/validación | `POST https://appleid.apple.com/auth/token` |
| Revocación | `POST https://appleid.apple.com/auth/revoke` |

## 4. `POST /api/v1/auth/apple`

Crea una cuenta Kalorias o inicia sesión en la ya vinculada al `sub` verificado de Apple. Es una
ruta pública en el sentido de que aún no hay bearer de Kalorias; la credencial es la respuesta de
Apple, verificada por el servidor.

### Petición

```http
POST /api/v1/auth/apple HTTP/1.1
Content-Type: application/json
Accept: application/json
X-Request-Id: <UUID opcional generado por el cliente>
```

```json
{
  "identityToken": "<JWT compacto de Apple>",
  "authorizationCode": "<código Apple de un solo uso>",
  "nonce": "<nonce original de un solo uso generado por iOS>"
}
```

Reglas de entrada:

- Limitar el body a un tamaño pequeño (por ejemplo 32 KB) y rechazar cuerpos enormes antes de
  decodificar JSON/JWT.
- Los tres campos son obligatorios, no vacíos y tienen límites conservadores de longitud.
- La petición no contiene cuestionario, respuestas, email, nombre ni un Apple user id declarado
  por el cliente.
- V1 no pide scopes de nombre/email. El `sub` verificado es la identidad; un email nunca será clave
  única aunque un cliente futuro lo solicite.
- No registrar body, token, código ni nonce. La redacción se aplica también al proxy/APM, antes de
  que un error pueda capturar la petición.

### Algoritmo de verificación

Usar una librería OpenID Connect/JWT mantenida; no implementar la criptografía a mano.

1. Parsear el JWT con límites estrictos de tamaño/segmentos. Rechazar `alg=none`, algoritmos no
   admitidos y cabeceras críticas desconocidas.
2. Resolver por `kid` la clave en el conjunto público actual de Apple, siempre sobre TLS. Cachear
   según las cabeceras HTTP y, ante un `kid` nuevo, refrescar una vez para tolerar rotación. Una
   caída de Apple nunca desactiva la validación.
3. Verificar la firma y, como mínimo, estos claims:
   - `iss` exactamente `https://appleid.apple.com`;
   - `aud` contiene/es exactamente el client id nativo `com.quispe.kalorias.Kalorias`;
   - la hora del servidor es anterior a `exp`, con una tolerancia de reloj pequeña y documentada;
   - `iat` es razonable y no procede de un pasado/futuro sin límite;
   - el claim `nonce` coincide con la representación SHA-256 del nonce original que usó iOS;
   - `sub` existe, no está vacío y cabe en la columna.
4. Marcar el nonce/intento como de un solo uso durante al menos toda la vigencia de la respuesta de
   Apple. Repetir un nonce ya completado no crea otra familia de sesiones.
5. Canjear `authorizationCode` en el endpoint de tokens de Apple con el `client_id` configurado y
   un Apple `client_secret` generado por el servidor. Si la autorización nativa no usó redirect,
   no inventarlo en el canje; si se introduce en el futuro, debe coincidir exactamente.
6. Comprobar que el canje corresponde a la misma identidad/cliente ya verificados. Cualquier fallo
   de token o canje es fallo total de autenticación, nunca login parcialmente confiable.
7. Guardar el Apple refresh token cifrado para poder revocarlo al borrar la cuenta. Nunca devolver
   los tokens Apple a iOS. En una identidad existente, una respuesta sin refresh token nuevo no
   borra el válido ya guardado. Para una identidad nueva, no poder conservar una credencial
   revocable hace fallar el registro: no se crea una cuenta imposible de borrar correctamente.
8. En una transacción: insertar/leer por la identidad única `(issuer, subject)`, actualizar
   `last_authenticated_at`, crear una familia de refresh sessions Kalorias y confirmar.
9. Responder solo tras el commit. Una autorización válida nueva para el mismo `sub` siempre
   devuelve el mismo `user.id` interno.

No fijar el algoritmo del JWT copiándolo de un ejemplo antiguo. Validar según los metadatos y la
documentación actual de Apple, con una allow-list explícita en la librería elegida. La firma del
`client_secret` del desarrollador y la firma del identity token de Apple son operaciones distintas
y pueden usar tipos de clave/algoritmos diferentes.

### Respuesta correcta

`201 Created` para usuario nuevo y `200 OK` para uno existente:

```json
{
  "data": {
    "user": {
      "id": "9d92525d-df31-49d2-9625-ae7a6fb48745"
    },
    "session": {
      "tokenType": "Bearer",
      "accessToken": "<access token Kalorias>",
      "accessTokenExpiresAt": "2026-09-08T17:30:00Z",
      "refreshToken": "<token opaco y rotatorio>",
      "refreshTokenExpiresAt": "2026-12-07T17:15:00Z"
    },
    "onboarding": {
      "status": "required"
    }
  }
}
```

`onboarding.status` solo puede ser:

- `required`: no existe onboarding/plan confirmado; iOS puede enviar sus respuestas locales
  después del consentimiento separado.
- `complete`: ya existe onboarding/plan confirmado; iOS no envía ni sobrescribe con el payload
  local redundante.

Este estado sale de datos confirmados del servidor, nunca de preferencias del cliente.

### Errores

Formato común recomendado:

```json
{
  "error": {
    "code": "invalid_apple_credential",
    "message": "Authentication could not be completed."
  }
}
```

| Estado | `error.code` estable | Significado |
|---|---|---|
| `400` | `invalid_request` | Campos ausentes, mal formados o demasiado grandes |
| `401` | `invalid_apple_credential` | Fallo de firma, claims, nonce o canje de code |
| `409` | `auth_attempt_replayed` | Repetición de nonce/intento ya completado |
| `429` | `auth_rate_limited` | Límite antiabuso; incluir `Retry-After` |
| `503` | `apple_temporarily_unavailable` | Keys/token endpoint de Apple inaccesible tras reintento acotado |
| `500` | `auth_service_error` | Fallo interno de transacción/sesión |

El mensaje público es genérico. El detalle va al diagnóstico redactado, correlacionado con
`X-Request-Id`, sin revelar si un `sub`/usuario existe.

## 5. Sesiones propias de Kalorias

### `POST /api/v1/auth/refresh`

Petición:

```json
{ "refreshToken": "<token opaco rotatorio>" }
```

La respuesta contiene el mismo objeto `session` de `/auth/apple`, con access token nuevo y **refresh
token nuevo**. Tras rotar, invalidar el refresh presentado. Detectar la reutilización de uno ya
rotado invalida toda la familia.

Son contractuales estas propiedades, no una duración fija:

- access tokens cortos;
- refresh tokens con caducidad explícita y hash en base de datos;
- rotación en cada uso;
- logout, revocación Apple y borrado invalidan las familias afectadas;
- la validación comprueba issuer, audience, expiración, firma y revocación de usuario/sesión;
- respuestas con `Cache-Control: no-store`.

El despliegue elige las duraciones por configuración. El ejemplo usa 15 minutos de access y 90
días de refresh como valores iniciales; la app no los hardcodea y se guía por las fechas recibidas.

### `POST /api/v1/auth/logout`

Requiere `Authorization: Bearer <accessToken>` y el refresh actual en el JSON. Invalida la familia
Kalorias y devuelve `204 No Content`. Cerrar sesión no revoca el consentimiento Apple; borrar la
cuenta sí.

## 6. Envío autenticado del onboarding

### Obtener el cuestionario (sin cambios)

```http
GET /api/v1/kalorias/onboarding?stage=onboarding
Accept-Language: es
```

Sin bearer ni identificador de usuario/dispositivo. Se conservan `ETag` y caché pública.

### Enviar respuestas (cambia)

```http
POST /api/v1/kalorias/onboarding HTTP/1.1
Authorization: Bearer <access token Kalorias>
Content-Type: application/json
Idempotency-Key: 5C2F0B1E-9A3D-4E77-9E21-2F3A9C1B7D40
```

```json
{
  "sessionId": "5C2F0B1E-9A3D-4E77-9E21-2F3A9C1B7D40",
  "onboardingId": "plan_v1",
  "schemaVersion": 1,
  "contentVersion": 5,
  "locale": "es",
  "startedAt": "2026-09-07T10:14:02Z",
  "completedAt": "2026-09-07T10:16:41Z",
  "consent": {
    "privacyNoticeVersion": "2026-09-08",
    "healthDataConsentVersion": "2026-09-08",
    "grantedAt": "2026-09-08T17:15:30Z"
  },
  "answers": [
    {
      "questionId": "goal_primary",
      "type": "single_choice",
      "optionId": "lose_weight"
    },
    {
      "questionId": "weight_current",
      "type": "measure",
      "value": 84.4,
      "unit": "kg",
      "displayUnit": "lb",
      "displayComponents": { "lb": 186.0 }
    }
  ]
}
```

Los valores de versión de consentimiento del ejemplo son ilustrativos: producción los obtiene de
configuración aprobada. El contrato completo de respuestas existente se conserva:

| `type` | Forma de la respuesta |
|---|---|
| `info` | `questionId`, `type`, `acknowledged: true` |
| `single_choice` | `questionId`, `type`, `optionId` |
| `multi_choice` | `questionId`, `type`, `optionIds[]`, `customValues[]` |
| `text` | `questionId`, `type`, `value` string; o `skipped: true` si es opcional |
| `number` | `questionId`, `type`, `value` numérico |
| `date` | `questionId`, `type`, `value` `YYYY-MM-DD` |
| `measure` | `questionId`, `type`, `value` canónico, `unit`, `displayUnit`, `displayComponents` |
| cualquier opcional omitida | Entrada con `skipped: true`; una pregunta invisible no se envía |

Reglas del servidor:

1. Autenticar antes de leer/validar el payload de salud.
2. Exigir que `Idempotency-Key` sea igual al `sessionId` del body.
3. Acotar unicidad por `(user_id, ruta, sessionId)` y guardar un hash del body canónico.
4. Misma clave + mismo body devuelve exactamente el resultado original, incluso después de un
   timeout. Misma clave + body distinto responde `409 idempotency_payload_mismatch` sin trabajar.
5. Validar que las versiones de consentimiento siguen aceptadas y que `grantedAt` es razonable.
   Guardar un recibo separado/auditable; nunca inferir consentimiento solo porque haya respuestas.
6. Validar contra el `contentVersion` declarado: cada `questionId`, el `optionId` dentro de su
   pregunta, tipos, campos obligatorios, rangos/unidades canónicas, texto libre y `maxLength`.
7. Reevaluar `visibleIf` con las respuestas recibidas: exigir todas las obligatorias visibles y
   rechazar preguntas que debían estar ocultas. Nunca reinterpretar ids retirados contra la versión
   actual del cuestionario.
8. Tratar `optionId` como único dentro de su pregunta, no globalmente. Mantener `customValues`
   separado de `optionIds`; `null`/ausente no equivale a `skipped: true`.
9. En una transacción, guardar el onboarding, crear el plan inicial, marcar `onboarding_status` como
   `complete` y persistir la respuesta idempotente.
10. No registrar bodies, respuestas, textos libres, pesos, nacimiento, condiciones o detalle del
    plan. Logs operativos: id interno/sustituto diagnóstico de usuario, `sessionId`, request id,
    versiones, resultado, duración y rutas de campo inválidas sin el valor rechazado.

Respuesta correcta, tanto en primera ejecución como en replay idéntico:

```json
{
  "data": {
    "onboardingStatus": "complete",
    "planId": "89c941df-5897-4222-9397-1d7d444d6c8d"
  }
}
```

Responder `200 OK` en ambos casos.

Errores añadidos:

| Estado | `error.code` estable | Significado |
|---|---|---|
| `401` | `authentication_required` | Access ausente/inválido; no empezó trabajo de dominio |
| `409` | `onboarding_already_complete` | Cuenta completa y la petición no es su replay |
| `409` | `idempotency_payload_mismatch` | Misma clave con contenido diferente |
| `409` | `consent_version_outdated` | La app debe presentar el consentimiento vigente |
| `422` | `invalid_onboarding` | Errores estructurados de validación de campos |

Ante `onboarding_already_complete`, el cliente descarta el payload local redundante después de
reconfirmar el estado autenticado; no sobrescribe el plan existente.

## 7. Análisis de comida autenticado

El body y la respuesta definidos en
`specs/009-backend-meal-analysis/contracts/analyze-meal-v1.md` no cambian. Se añade:

```http
POST /api/v1/kalorias/analyzeMeal
Authorization: Bearer <access token Kalorias>
Content-Type: multipart/form-data; boundary=<generado>
```

Reglas:

- Autenticar y aplicar límites antes de parsear multipart o llamar al proveedor.
- Un `401` no analiza, no guarda foto y no consume cuota.
- El límite de producto principal usa `user_id`, no solo IP. Puede añadirse un techo por IP/
  dispositivo para abuso.
- No guardar la foto. Conservar caché desactivada, timeout, respuesta normalizada,
  `Retry-After` y `X-Request-Id` actuales.
- El cliente puede renovar una sola vez tras `401` y reenviar la misma foto porque el primer
  request no alcanzó el análisis.

## 8. Modelo de datos sugerido e invariantes

Los nombres son orientativos; los invariantes no.

### `users`

| Campo | Notas |
|---|---|
| `id` | UUID/ULID interno; único id de usuario que se devuelve a iOS |
| `onboarding_status` | `required`/`complete`, actualizado en la transacción que crea el plan |
| `created_at`, `updated_at`, `last_authenticated_at` | Fechas del servidor |
| `deletion_requested_at` | Reservado para una futura versión asíncrona; no es necesario en el contrato V1 síncrono |

### `external_identities`

| Campo | Notas |
|---|---|
| `user_id` | Foreign key |
| `provider` | Constante `apple` |
| `issuer` | `iss` verificado exacto |
| `subject` | `sub` verificado, protegido como identificador personal |
| `apple_refresh_token_encrypted` | Cifrado, nunca registrado/devuelto |
| `credential_state` | active/revoked/deleted según eventos conocidos |

Constraint única: `(provider, issuer, subject)`. Nunca enlazar o fusionar por email. Si el token
verificado incluye email aunque no se haya pedido como campo de perfil, ignorarlo en V1: no hay
propósito de producto para almacenarlo.

### `refresh_sessions`

Guardar `user_id`, family id, hash del refresh opaco actual, fechas de creación/caducidad/rotación/
revocación y metadatos mínimos de sesión. Nunca el refresh reutilizable en claro.

### `onboarding_submissions`

Guardar `user_id`, `session_id`, versiones de cuestionario, timestamps, respuestas normalizadas
bajo controles de datos de salud, referencia al recibo de consentimiento, `plan_id`/resultado y
hash canónico. Constraint única: `(user_id, session_id)`.

### `deletion_operations`

Para sobrevivir a una respuesta `204` perdida después de borrar usuario y sesiones, conservar un
recibo mínimo y temporal: HMAC del `Idempotency-Key`, HMAC del access token presentado, resultado
final (`204`), `completed_at` y `expires_at`. No conservar respuestas, identidad Apple, email, perfil
ni id de usuario reversible. La clave HMAC vive en el secret manager y la retención es corta y
documentada (por ejemplo, siete días), suficiente para reintentos del cliente.

### Invariantes

- Un `(issuer, subject)` de Apple pertenece a un único usuario Kalorias.
- No existe onboarding persistido sin usuario confirmado y recibo de consentimiento.
- `onboarding_status=complete` implica que el plan inicial referenciado hizo commit.
- Repetir una sesión devuelve el resultado; nunca crea un segundo plan.
- Un usuario/sesión eliminado o revocado no puede renovar ni usar access tokens.

## 9. Borrado de cuenta

### Endpoint

```http
DELETE /api/v1/account
Authorization: Bearer <access token Kalorias>
Idempotency-Key: <UUID de esta solicitud de borrado>
```

V1 exige sesión válida/reciente según la política del backend y confirmación destructiva en la app.
Si hace falta autenticación más reciente, devolver `reauthentication_required` para que iOS invoque
Apple otra vez; nunca pedir la contraseña Apple.

Proceso del servidor:

1. Autenticar y reservar idempotentemente la operación sin invalidar todavía la sesión actual; una
   caída temporal de Apple debe permitir al usuario reintentar.
2. Usar el Apple refresh token cifrado (u otro token válido) contra `/auth/revoke`, con un
   `client_secret` generado en servidor. Si Apple responde que el token ya era inválido/revocado,
   este paso se considera terminado. Un fallo transitorio deja cuenta/sesión intactas y responde un
   error seguro y reintentable.
3. Tras confirmar la revocación, invalidar atómicamente todas las sesiones Kalorias y borrar/
   anonimizar cuenta, onboarding, perfil ligado al consentimiento, planes y demás datos sin
   obligación legal documentada de conservación. Aplicar también la política a backups y colas.
4. Eliminar refresh token Apple y vínculo externo cuando ya no sean necesarios para completar el
   borrado.
5. Antes de invalidar la última autoridad, guardar el recibo mínimo de `deletion_operations`. La ruta
   es idempotente: repetir exactamente el mismo bearer y `Idempotency-Key` devuelve el `204` guardado,
   no resucita datos ni falla porque la fila del usuario ya no exista.

La comprobación del recibo es una excepción **solo para esta ruta** y se ejecuta antes de devolver el
`401` que produciría una sesión ya eliminada. Compara ambos HMAC en tiempo constante, devuelve
únicamente el `204` previamente confirmado y no restaura sesión ni autoriza otra llamada. Un bearer
distinto, una clave distinta o un recibo caducado siguen el flujo normal de autenticación/error. Así,
si iOS pierde la primera respuesta después del commit, conserva token y clave y puede conocer el
resultado sin crear otra cuenta ni tratar un `401` ambiguo como borrado.

El contrato de cliente V1 exige que borrado y revocación terminen de forma síncrona y que la ruta
devuelva `204 No Content`. `202 Accepted` **no es éxito para esta versión de la app**: iOS conserva
sesión y datos locales ante cualquier respuesta distinta de `204`. Si el backend necesita un proceso
asíncrono en el futuro, debe versionar el contrato y añadir un recurso/recibo de estado con polling
autenticado o reanudable antes de que el cliente pueda adoptarlo; nunca debe llamarlo “completo” antes
de serlo.

Errores estables:

| Estado | `error.code` | Significado |
|---|---|---|
| `401` | `authentication_required` | Autoridad ausente/inválida y sin recibo exacto de borrado completado |
| `403` | `reauthentication_required` | La política exige Apple reciente antes de iniciar el borrado |
| `409`/`503` | `apple_revocation_pending` | Revocación no confirmada; cuenta/sesión/datos locales se conservan para reintento |
| `429` | `account_action_rate_limited` | Límite alcanzado; incluir `Retry-After` |
| `500` | `account_deletion_error` | El commit no se confirmó; iOS conserva datos y muestra reintento |

Apple exige que una app que crea cuentas permita iniciar su borrado dentro de la app; con Sign in
with Apple deben revocarse sus tokens: [Offering account deletion in your
app](https://developer.apple.com/support/offering-account-deletion-in-your-app/).

## 10. Privacidad y seguridad

- Tratar respuestas y planes como datos de salud/perfil. Cifrar almacenamiento sensible y usar
  TLS; producción no admite HTTP plano.
- Desactivar body logging en load balancer, framework, excepciones, APM y middleware de debug, no
  solo en los `logger` de la aplicación.
- Redactar `Authorization`, cookies, `identityToken`, `authorizationCode`, `nonce`, `refreshToken`
  y client secrets antes de cualquier captura.
- Nunca llevar credenciales o respuestas en URLs/query strings.
- Rate limit conservador en auth por IP y otras señales, sin revelar existencia de cuentas.
- Validar tamaños/strings antes de almacenar. V1 no acepta nombre/email de Apple.
- Claves Apple/Kalorias en secret manager gestionado, con acceso auditado, rotación y separación
  entre debug/staging/production.
- Usar UTC del servidor para recibos; conservar `startedAt`/`completedAt` del cliente como hechos
  del recorrido del usuario.
- Respuestas de error con códigos estables y mensajes seguros. Fallos JWT/proveedor detallados solo
  en servidor.
- Definir borrado/retención de backups en la política de privacidad. La base jurídica y el texto
  exacto del consentimiento requieren aprobación de producto/legal; la API debe poder demostrar
  qué versión aceptó el usuario.

## 11. Revocación y notificaciones de Apple

Como mínimo:

- iOS consulta el estado con `ASAuthorizationAppleIDProvider` y observa la notificación local de
  credenciales revocadas.
- El backend rechaza usuarios eliminados/revocados y puede invalidar todas sus sesiones.
- El borrado de cuenta llama al endpoint de revocación de Apple.

Antes de producción, configurar notificaciones server-to-server sobre el App ID primario. Validar
criptográficamente el `signedPayload` antes de actuar. Ante revocación de consentimiento o borrado
de cuenta, marcar la identidad externa, invalidar sesiones y aplicar la política de datos. El
handler es idempotente y nunca confía en JSON sin firma.

No consultar el token endpoint de Apple en cada request o launch. Seguir su guía vigente de
frecuencia/refresh: una verificación excesiva puede ser limitada por Apple.

## 12. Matriz de pruebas del backend

### Autenticación Apple

- Un `sub` nuevo válido crea exactamente un usuario y una familia de sesión (`201`).
- Un `sub` existente válido devuelve el mismo usuario (`200`).
- Dos primeros logins concurrentes del mismo `sub` crean un usuario (probar race + constraint).
- Falla issuer, audience, exp, firma, `kid`, nonce, claim ausente o JWT mal formado.
- Un nonce/intento repetido no crea otra sesión.
- Código Apple reutilizado, inválido o caducado falla de forma cerrada.
- Un `kid` nuevo refresca claves una vez; la rotación nunca desactiva validación.
- Caída de Apple responde `503` acotado, sin usuario/sesión a medias.
- Body/token/code/nonce no aparecen en logs, proxy ni fixtures de APM.
- La respuesta `required`/`complete` sale del estado confirmado.

### Sesiones Kalorias

- Access válido alcanza rutas protegidas; ausente/caducado/revocado/audience errónea recibe `401`
  antes del trabajo de dominio.
- Refresh rota ambos tokens; reutilizar el anterior revoca la familia.
- Logout revoca su familia; borrado revoca todas.
- Auth/token llevan `Cache-Control: no-store` también en proxy.

### Onboarding

- El GET público funciona sin auth y no acepta respuestas.
- POST sin auth/inválida da `401` antes de procesar body.
- Usuario registrado + consentimiento válido crea un plan y marca complete atómicamente.
- Mismo usuario/clave/body devuelve original; clave igual/body diferente da `409`.
- Mismo `sessionId` en dos usuarios queda correctamente aislado.
- Una cuenta completa no puede ser sobrescrita salvo replay exacto.
- Consentimiento ausente, falso o desactualizado no persiste respuestas.
- Siguen pasando validaciones de visibilidad, ids, opciones, unidad, rango, texto y versión.
- Payload y valores rechazados no aparecen en logs/APM.

### Análisis y borrado

- Análisis anónimo no parsea/guarda foto, no llama al proveedor y no consume límite.
- Dos usuarios tras una misma IP tienen límites de producto independientes.
- Borrado revoca Apple, sesiones y datos, y es idempotente.
- Perder el primer `204` y repetir bearer + clave devuelve `204` desde el recibo temporal; cambiar
  cualquiera de ambos no revela ni concede acceso.
- Tokens de usuario eliminado no recuperan acceso.
- Notificación Apple firmada válida revoca; falsa o repetida no ejecuta destrucción indebida.

## 13. Checklist de despliegue

- [ ] Capability Sign in with Apple activa en el App ID exacto de producción.
- [ ] Team ID, Client ID, Key ID y `.p8` en el secret manager de cada entorno.
- [ ] Generación/rotación del Apple client secret probada; ningún secreto en repo/app.
- [ ] Caché y rotación de claves públicas Apple probadas.
- [ ] Migraciones y constraints únicas aplicadas antes de publicar `/auth/apple`.
- [ ] `/auth/apple`, `/auth/refresh`, `/auth/logout`, onboarding autenticado y borrado bajo TLS.
- [ ] GET cuestionario público; POST onboarding y `analyzeMeal` con bearer obligatorio.
- [ ] Redacción de headers/bodies verificada con petición canaria en proxy/framework/APM.
- [ ] Rate limit por usuario en análisis y límites antiabuso en auth.
- [ ] Borrado + revoke Apple probado con una cuenta de test desechable.
- [ ] Recibo temporal de borrado, replay exacto tras `204` perdido y caducidad/limpieza probados.
- [ ] Firma e idempotencia de notificaciones server-to-server probadas.
- [ ] Versiones/textos de privacidad y consentimiento aprobados/configurados.
- [ ] `X-Request-Id` en cada respuesta y correlación segura comprobada.
- [ ] Tests/briefs antiguos sin auth actualizados para no permitir una regresión silenciosa.

## 14. Definición de terminado

Backend está listo para iOS cuando puede autenticar a un usuario sin recibir ningún dato del
onboarding, responde tras confirmar una cuenta con una sesión Kalorias renovable y el estado real
del onboarding, acepta después el payload consentido/idempotente bajo ese usuario, y bloquea a los
clientes anónimos en el POST de onboarding y en análisis. Revocación, borrado, redacción de logs y
la matriz de fallos forman parte de esta definición, no son hardening posterior.
