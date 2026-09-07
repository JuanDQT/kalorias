# Kalorias: el onboarding dinámico, del lado del servidor

**Para**: quien monte el endpoint en el proyecto del backend
**Contrato completo**: [`onboarding-contract-v1.md`](onboarding-contract-v1.md)

La app no conoce ninguna pregunta. Conoce **siete tipos de pregunta** y las dibuja a partir de un
JSON que sirve el backend. Añadir, quitar, reordenar o reescribir preguntas es editar un fichero
y desplegar: **no hay release de la App Store por medio**.

---

## 1. Qué hay que copiar

Tres ficheros, y nada más:

| Fichero | Qué es | ¿Se despliega? |
|---|---|---|
| `questionnaire.source.json` | El cuestionario. La única fuente de verdad | Sí |
| `questionnaire.schema.json` | JSON Schema 2020-12 que lo valida | No, sólo CI |
| `validate.py` | Las comprobaciones que un JSON Schema no puede hacer | No, sólo CI |

**Dependencias en tiempo de ejecución: ninguna.** El endpoint lee un fichero, filtra un array y
responde. No hay plantillas, ni base de datos, ni motor de reglas. Si el cuestionario acaba en
una tabla de la base de datos habrá que mantener migraciones para cada cambio de copy, que es
precisamente el coste que este diseño evita.

**Dependencias en CI**: `python3` (biblioteca estándar) y, opcionalmente, `pip install
jsonschema`. Sin `jsonschema` el validador avisa y ejecuta igualmente el resto de comprobaciones,
que son las que más rompen.

---

## 2. Los dos endpoints

### `GET /api/v1/kalorias/onboarding`

| | |
|---|---|
| **Parámetro** | `stage`, opcional: `onboarding` (por defecto) o `profile` |
| **Idioma** | Cabecera `Accept-Language`. Se responde con el `locale` realmente aplicado |
| **Autenticación** | Ninguna, igual que `analyzeMeal` |
| **Caché** | `Cache-Control: public, max-age=300` + `ETag`. Es contenido público y no cambia cada minuto |

Toda la lógica del handler:

```
1. cargar questionnaire.<locale>.json  (si no existe el idioma, caer a `es`)
2. quedarse con las preguntas cuyo `stage` == el pedido
3. quitar las secciones que se hayan quedado sin preguntas
4. borrar el campo `stage` de cada pregunta   ← la app no lo necesita
5. responder { "data": <lo anterior> }
```

El paso 4 no es cosmético: `stage` es una decisión de producto del servidor, y filtrar por él en
el cliente significa enviar al dispositivo preguntas que no se van a mostrar.

**La ruta de envío no viaja en la respuesta.** La app conoce sus propios endpoints por
`BackendEnvironment`. Una URL de destino que llega dentro de un JSON es una redirección abierta
con otro nombre.

### `POST /api/v1/kalorias/onboarding`

Cuerpo: `application/json`, el documento descrito en `answers-v1.example.json`. Una sola petición
al terminar, no una por respuesta.

| | |
|---|---|
| **Idempotencia** | Cabecera `Idempotency-Key` = el `sessionId` del cuerpo. La app reintenta con la misma clave tras un timeout, y no deben salir dos planes |
| **`422`** | Formato Laravel, igual que `analyzeMeal`: `{"message": "…", "errors": {"answers.3.optionId": ["…"]}}` |
| **Respuesta** | `{ "data": { "planId": "…" } }` o similar. Fuera del alcance de este documento |

Validación mínima en servidor, porque el cliente **puede estar desactualizado**:

- que cada `questionId` exista en el `contentVersion` que declara el cuerpo;
- que cada `optionId` exista **en esa pregunta** (los ids sólo son únicos dentro de su pregunta:
  `yes` aparece en tres);
- que estén todas las obligatorias que resultan visibles al reevaluar los `visibleIf` con las
  respuestas recibidas. Reevaluarlos en el servidor es lo que detecta un cliente con un bug o
  manipulado, que envía `allergies` habiendo respondido `has_allergies: "no"`;
- que los `measure` lleguen en la unidad canónica y dentro de rango;
- que `customValues` venga recortado y por debajo de `maxLength`. Es el único texto libre del
  cuestionario y llega directo de un teclado.

---

## 3. Cómo se actualiza el formulario

```bash
$EDITOR questionnaire.source.json     # 1. editar
# 2. subir contentVersion
python3 validate.py questionnaire.*.json   # 3. validar, todos los idiomas a la vez
git commit && deploy                       # 4. desplegar
```

Al abrir la app, el usuario siguiente ve el cuestionario nuevo. Nadie actualiza nada.

### Reglas al editar

| Regla | Por qué |
|---|---|
| **Un `id` no se reutiliza jamás para otra cosa** | Hay respuestas guardadas con ese id. Cambiarle el significado corrompe el histórico en silencio, sin que falle nada |
| **Cambiar el `type` de una pregunta = pregunta nueva, id nuevo** | La forma de la respuesta cambia |
| **Añadir opciones es seguro. Quitarlas no** | Las respuestas antiguas apuntan a la opción que ya no existe. Márcala como retirada en tu almacén antes de borrarla del JSON |
| **Reescribir textos es libre** | Nada depende del texto: las respuestas viajan como ids |
| **`contentVersion` sube en cada cambio** | Viaja en el envío y es lo que permite interpretar un `optionId` de hace tres meses |
| **`schemaVersion` sólo sube si cambia la *estructura*** | Un tipo nuevo, un campo nuevo. Obliga a release de la app |

### Idiomas

Un fichero por idioma (`questionnaire.es.json`, `questionnaire.en.json`), con **los mismos ids**.
`validate.py` con varios ficheros compara las estructuras y falla si a una traducción le falta
una opción o le sobra una burbuja, que es exactamente lo que pasa al traducir.

Los textos van ya traducidos en el JSON, no son claves de `Localizable.xcstrings`: si lo fueran,
añadir una pregunta exigiría una release, que es lo que este diseño evita.

---

## 4. Lo que la app sigue necesitando

La pregunta era si a la app le basta con «llamar a un endpoint y ya». Casi:

**Sí, es todo lo que hay de red**: un `GET` al empezar y un `POST` al terminar. No hay llamada
por pregunta ni estado de sesión en el servidor.

**Pero la app aporta lo que no se puede serializar**:

1. **Siete renderizadores**, uno por `type`. Es la mayor parte del trabajo de cliente, y es lo
   que permite que el JSON sea sólo contenido.
2. **La máquina de estados**: visibilidad, retroceso, edición y poda de respuestas invalidadas
   (§6 del contrato). Es lo más fácil de hacer mal.
3. **Una copia del cuestionario en el bundle.** Sin ella, un usuario sin cobertura en el primer
   arranque no puede ni empezar. Se actualiza en cada release y es el respaldo, no la fuente.
4. **Persistencia local de `answers`** tras cada respuesta, para reanudar si la app muere.
5. **Rechazar un `schemaVersion` mayor** que el que entiende, cayendo a la copia del bundle. Nunca
   saltarse en silencio una pregunta de tipo desconocido: si es obligatoria, el plan se calcula
   con datos que faltan.

---

## 5. Protección de datos

El cuerpo del `POST` es **dato de salud** según el RGPD: condiciones médicas, embarazo, peso,
fecha de nacimiento. No es una nota al pie:

- base legal explícita y consentimiento separado del de la cuenta;
- **fuera de logs y de analítica de producto**. En concreto, no volcar el cuerpo de la petición
  en el log de errores, que es como acaba ahí el 90% de las veces;
- borrado real al borrar la cuenta, incluidas copias de seguridad y colas;
- `customValues` es texto libre escrito por el usuario: puede contener cualquier cosa y hay que
  tratarlo como el resto.

Conviene decidirlo antes de implementar, no después.
