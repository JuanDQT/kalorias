# Kalorias: cómo la app pasa a usar el endpoint del servidor

**Para**: quien adapte la app Kalorias (iOS)
**Endpoint**: `POST /api/v1/kalorias/analyzeMeal` (v1)
**Contrato completo**: [`specs/004-gemini-ai-endpoints/contracts/kalorias-analyzemeal-v1.md`](../specs/004-gemini-ai-endpoints/contracts/kalorias-analyzemeal-v1.md)

Este documento es el resumen que se le transmite a la app. El contrato enlazado arriba manda
si algo no coincide.

---

## Lo que cambia

**El backend ya habla con Gemini. La app deja de hacerlo.**

Hasta ahora la app llevaba la clave de Gemini y llamaba al proveedor directamente. Ahora llama a
**nuestro** servidor, que es el único que conoce proveedor, modelo, prompt y esquema. Por tanto:

- **Quitar la clave de Gemini del binario** y todo el código que construía la petición a
  `generativelanguage.googleapis.com`: prompt, `responseSchema`, base64 de la imagen,
  `maxOutputTokens`. Todo eso lo fija el servidor.
- La app solo envía una foto y recibe un análisis ya normalizado.

---

## El endpoint

| | |
|---|---|
| **Método** | `POST` |
| **Ruta** | `{BASE_URL}/api/v1/kalorias/analyzeMeal` |
| **Cuerpo** | `multipart/form-data`, campo **`photo`** (nombre exacto) |
| **Formato de la foto** | **JPEG obligatorio**, máximo **8 MB** |
| **Autenticación** | **Ninguna.** No enviar cabeceras de auth |
| **Límite** | **10/min** y **100/día** por IP. Al excederlo: `429` con `Retry-After` |
| **Caché** | La respuesta llega con `Cache-Control: no-store, private`. No cachear nunca |
| **Timeout del cliente** | **≥ 35 s**: el servidor espera hasta 30 s la respuesta del modelo |

No hay ningún otro parámetro. No fijar `Content-Type` a mano: que lo ponga el cliente HTTP con su
propio boundary de multipart.

---

## Respuesta `200`

```json
{
  "data": {
    "foodDetected": true,
    "totalCalories": 615,
    "foods": [
      {
        "name": "Arroz blanco",
        "calories": 205,
        "protein": 4.3,
        "carbs": 44.5,
        "fat": 0.4,
        "region": { "x": 0.12, "y": 0.31, "width": 0.4, "height": 0.28 }
      },
      {
        "name": "Pechuga de pollo",
        "calories": 410,
        "protein": 62.0,
        "carbs": 0,
        "fat": 16.2,
        "region": null
      }
    ]
  }
}
```

Atención al envoltorio **`data`** en la raíz.

### Campos

| Campo | Tipo | Notas |
|---|---|---|
| `foodDetected` | `bool` | Falso ⇒ `foods` vacío y `totalCalories` 0 |
| `totalCalories` | `int` | **Siempre** la suma de `foods[].calories`. Lo calcula el servidor |
| `foods[].name` | `string` | Nunca vacío |
| `foods[].calories` | `int` | ≥ 0 |
| `foods[].protein` | `float\|null` | Gramos |
| `foods[].carbs` | `float\|null` | Gramos |
| `foods[].fat` | `float\|null` | Gramos |
| `foods[].region` | `objeto\|null` | `null` cuando no se pudo localizar el alimento |
| `region.x` | `float` | Borde izquierdo, `0..1`, **desde la izquierda** |
| `region.y` | `float` | Borde superior, `0..1`, **desde arriba** |
| `region.width` | `float` | Proporción del ancho, > 0 |
| `region.height` | `float` | Proporción del alto, > 0 |

---

## Las tres cosas que más fácilmente se implementan mal

### 1. `region` ya viene en proporciones `0..1`, con origen arriba-izquierda

**No** es la caja `{ymin, xmin, ymax, xmax}` en escala 0–1000 del proveedor.

- **No dividir entre 1000.**
- **No reordenar ejes**: el formato nativo del modelo pone la Y primero; la conversión ya la hizo el
  servidor. Intercambiar el par no da ningún error, simplemente recorta la parte equivocada.
- Al ser proporciones, valen tal cual sobre la copia reducida de la foto (lado mayor 1024) sin
  ningún desplazamiento. Ese es justamente el motivo de que no sean píxeles.

### 2. `protein` / `carbs` / `fat` pueden ser `null`, y `null` no es `0`

`null` significa "el análisis no lo aportó". `0` significa "no tiene". Son afirmaciones distintas y
deben verse distintas en la UI (por ejemplo "—" frente a "0 g").

### 3. `region: null` es normal y no invalida el alimento

Un alimento sin zona sigue teniendo nombre y calorías; solo se queda sin miniatura.
**No descartar el alimento** por no tener `region`.

### Además

**`totalCalories` ya viene calculado** y siempre cuadra con el detalle. La app puede dejar de
calcularlo; si lo recalcula saldrá lo mismo, pero la fuente de verdad es la respuesta.

---

## Sin comida no es un error

```json
{ "data": { "foodDetected": false, "totalCalories": 0, "foods": [] } }
```

Llega como `200`. Es "no he reconocido comida", no un fallo.

---

## Errores

| Código | Qué significa | Qué hace la app |
|---|---|---|
| `422` | La foto no vale: falta, no es JPEG, o pasa de 8 MB. Cuerpo: `{"message": "...", "errors": {"photo": ["..."]}}`, con los mensajes ya en español | Mostrar el mensaje y pedir otra foto. **No reintentar** |
| `413` | El cuerpo supera lo que admite el servidor web. Puede no traer JSON | Tratar como "foto demasiado grande" |
| `429` | Límite de peticiones superado | Respetar `Retry-After`. No reintentar en bucle |
| `503` | `{"message": "El servicio de análisis no está disponible. Inténtalo de nuevo más tarde."}` | Mostrar ese mensaje. Reintento manual del usuario; si es automático, con backoff |

El `503` es **deliberadamente indistinguible**: cubre proveedor caído, lento, sin cuota, credencial
ausente o inválida, y respuesta ilegible o truncada. La app no puede hacer nada distinto en cada
caso, así que **no hay que intentar inferir la causa**. La causa concreta queda en el registro del
servidor, que es donde sirve de algo.

---

## Para soporte: `X-Request-Id`

Toda respuesta trae la cabecera **`X-Request-Id`**. Si la app la registra —o la envía en la
petición, que el servidor la respeta— un incidente reportado por un usuario se puede rastrear en
nuestros logs. Recomendado incluirla en los informes de error.

---

## Garantías del servidor

- O el análisis está completo y es coherente, o hay error. Nunca respuestas a medias.
- La foto **no se almacena ni se registra**: se procesa y se descarta. Del análisis solo se registran
  proyecto, resultado, duración y tamaño.
- La respuesta nunca revela qué proveedor de IA hay detrás, qué modelo, ni sus mensajes o códigos.
- El contrato va versionado en la ruta (`v1`): una `v2` futura no rompería esta.

---

## Comprobación rápida

```bash
# Éxito
curl -s -X POST {BASE_URL}/api/v1/kalorias/analyzeMeal -F "photo=@plato.jpg"

# El total siempre cuadra con el detalle
curl -s -X POST {BASE_URL}/api/v1/kalorias/analyzeMeal -F "photo=@plato.jpg" \
  | jq '.data.totalCalories == ([.data.foods[].calories] | add // 0)'
```
