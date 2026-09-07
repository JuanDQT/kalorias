# Contrato: onboarding dinámico en formato chat, v1

**Estado**: borrador de diseño, previo a `/speckit-specify` | **Fecha**: 2026-09-07
**Para el backend**: [`backend-brief.md`](backend-brief.md)

El backend sirve un JSON y la app dibuja el chat a partir de él. La app no conoce ninguna
pregunta: conoce **tipos de pregunta**. Añadir, quitar o reordenar preguntas es un cambio de
contenido en el servidor, no una release.

Ficheros de este directorio:

| Fichero | Qué es |
|---|---|
| `questionnaire.es.json`, `questionnaire.en.json` | El cuestionario, un fichero por idioma. **Única fuente de verdad**, los copia el backend |
| `questionnaire.schema.json` | JSON Schema 2020-12 que lo valida |
| `validate.py` | Las comprobaciones que un JSON Schema no puede hacer, y la comparación entre idiomas. Sólo stdlib |
| `answers-v1.example.json` | Lo que la app envía al terminar |
| `backend-brief.md` | Los dos endpoints y cómo se actualiza el formulario |
| este documento | Las reglas que ningún JSON puede expresar por sí solo |

El fichero fuente **no lleva el sobre `data`** ni se sirve tal cual: el servidor filtra por
`stage`, borra ese campo y envuelve el resto. Ver `backend-brief.md` §2.

---

## 1. Petición

```
GET {BASE_URL}/api/v1/kalorias/onboarding?stage=onboarding
Accept-Language: es
```

`stage` es opcional y vale `onboarding` (por defecto) o `profile`. Ver §2.1.

Respuesta `200`, con el sobre `data` que ya usa `analyzeMeal`:

```json
{ "data": { "onboardingId": "plan_v1", "schemaVersion": 1, "contentVersion": 3, "locale": "es", "sections": [...] } }
```

| Campo | Para qué |
|---|---|
| `onboardingId` | Qué cuestionario es. Permite tener varios (`plan_v1`, `winback_v1`) |
| `schemaVersion` | Qué **estructura** entiende la app. Ver §7 |
| `contentVersion` | Qué **redacción** es. Sube con cada cambio de texto u opciones |
| `locale` | El idioma que realmente devolvió el servidor, que puede no ser el pedido |

**Los textos vienen ya traducidos.** No son claves de `Localizable.xcstrings`: si lo fueran,
añadir una pregunta exigiría una release, que es justo lo que este diseño evita. El servidor
traduce según `Accept-Language` y responde con el `locale` que aplicó.

**La ruta de envío no viaja en el JSON.** La app conoce sus propios endpoints vía
`BackendEnvironment`. Una URL de destino controlada por la respuesta es una redirección abierta
con otro nombre.

---

## 2. Estructura

`sections[]` → `questions[]`. La sección es **solo presentación**: un título de grupo y el
progreso. El chat es un único hilo continuo; el usuario no "cambia de pantalla" al cambiar de
sección, solo aparece una cabecera nueva.

```json
{ "id": "goals", "title": "Tus objetivos", "subtitle": "Para saber a dónde vamos",
  "countsTowardProgress": true, "questions": [ ... ] }
```

Campos de una pregunta:

| Campo | Oblig. | Notas |
|---|---|---|
| `id` | sí | **Único en todo el cuestionario**, no solo dentro de su sección. Es la clave de la respuesta |
| `stage` | sí | `onboarding` o `profile`. Ver §2.1. Sólo existe en el fichero fuente |
| `type` | sí | Ver §3 |
| `prompt` | sí | **Array de strings, siempre.** Cada elemento es una burbuja de chat, en orden |
| `required` | no | `true` por defecto |
| `skipLabel` | no | Solo si `required: false`. Texto del botón de saltar |
| `visibleIf` | no | Ver §4 |
| `options` | según tipo | Solo `single_choice` / `multi_choice` |
| `allowsCustom` | no | Solo `multi_choice`. Ver §3 |
| `validation` | no | Ver §3, por tipo |
| `crossChecks` | no | Avisos que dependen de otra respuesta. Ver §5 |

`prompt` es un array incluso cuando tiene un solo elemento. Un campo que a veces es string y a
veces array es la forma más barata de tener un `if` en cada capa del stack.

### 2.1 `stage`: qué se pregunta al entrar y qué después

Cada pregunta declara si forma parte del **onboarding** —lo que hace falta para calcular el
primer plan— o del **perfil**, un tramo corto que se ofrece después, cuando el usuario ya tiene
su plan y algo que perder si se va.

El servidor sirve un `stage` por petición y la app reutiliza el mismo chat para los dos. Mover
una pregunta de un tramo a otro es cambiar una palabra en el fichero fuente.

Regla que `validate.py` comprueba: **una pregunta de `onboarding` no puede depender vía
`visibleIf` de una de `profile`.** Al revés sí, porque las respuestas del onboarding ya están
guardadas cuando se abre el perfil.

Hoy sólo `disliked_foods` está en `profile`, y el motivo está en §10.

### Opciones

```json
{ "id": "lose_weight", "title": "Perder peso", "description": "Bajar grasa manteniendo el músculo",
  "emoji": "🔥", "exclusive": false }
```

`description` y `emoji` son opcionales. `emoji` es un carácter Unicode, no un nombre de asset ni
una URL: se renderiza en cualquier tamaño de Dynamic Type sin descargar nada y sin que una
imagen rota deje la opción sin identificar.

`exclusive: true` (solo en `multi_choice`) marca la opción que anula a las demás — «Como de
todo», «Ninguna». Al marcarla se deseleccionan las otras; al marcar cualquier otra se
deselecciona ella. Sin esto acabas con «Ninguna + Brócoli» en la base de datos.

---

## 3. Tipos de pregunta

| `type` | Interacción | Avanza |
|---|---|---|
| `info` | No es pregunta: burbujas y un botón | Al pulsar `continueLabel` |
| `single_choice` | Lista de opciones, una sola | **Al tocar la opción**, sin confirmar |
| `multi_choice` | Lista de opciones, varias | Al pulsar `confirmLabel` |
| `text` | Campo de texto | Al enviar |
| `number` | Teclado numérico con unidad fija | Al enviar |
| `date` | Selector de fecha | Al confirmar |
| `measure` | Rueda con cambio de unidad | Al confirmar |

`info` sí ocupa una entrada en `answers` (`acknowledged: true`). Sin eso, volver atrás desde una
burbuja informativa no sabe si ya se mostró.

### `validation` por tipo

| Tipo | Campos |
|---|---|
| `multi_choice` | `minSelections`, `maxSelections` |
| `text` | `minLength`, `maxLength` |
| `number` | `min`, `max`, `step`, `unit`, `decimals` |
| `date` | dentro de `date`: `minDate`, `maxDate`, `default`, `mode`, `displayFormat` |
| `measure` | dentro de `measure`, por componente |

### Fechas relativas

`minDate`, `maxDate` y `default` aceptan un ISO-8601 (`1993-04-18`) **o** un token relativo:
`today`, `today-16y`, `today+30d`. Unidades `d`, `m`, `y`.

Existen porque el cuestionario también viaja embebido en la app como copia de respaldo (§7), y
un `maxDate` fijo escrito hoy convierte a un chaval de 16 años en uno de 17 el año que viene.
El token se resuelve **en el dispositivo, en su zona horaria**, en el momento de mostrar la
pregunta.

`today-16y` en `birth_date` es una decisión de producto, no un detalle: un plan de déficit
calórico para menores no es algo que esta app deba generar.

### `measure`: la rueda con unidades

```json
"measure": {
  "widget": "wheel",
  "canonicalUnit": "kg",
  "defaultUnit": "kg",
  "units": [
    { "id": "kg", "label": "kg",
      "components": [ { "id": "kg", "min": 30, "max": 250, "step": 0.1, "default": 70, "decimals": 1, "toCanonical": 1 } ] },
    { "id": "lb", "label": "lb",
      "components": [ { "id": "lb", "min": 66, "max": 550, "step": 0.2, "default": 154, "decimals": 1, "toCanonical": 0.45359237 } ] }
  ]
}
```

Toda unidad tiene un array `components`, tenga uno o dos. La altura en `ft/in` son dos ruedas
con dos componentes; los kilos, una rueda con uno. **Una sola regla de conversión**:

```
canónico = Σ (valor_componente × toCanonical)
```

`ft/in` con un único factor de conversión no se puede expresar, y es exactamente el caso que
aparece en cuanto la app sale de España.

**Al cambiar de unidad no se recalcula el valor canónico.** Se convierte el canónico a la unidad
nueva y se ajusta al `step` **solo para mostrarlo**. El canónico se reescribe únicamente cuando
el usuario mueve la rueda. Si cada cambio de unidad reescribiera el canónico, kg → lb → kg diez
veces desplazaría el peso del usuario redondeo a redondeo.

**`defaultUnit` es una sugerencia, no una orden.** Si el sistema de medida del dispositivo
(`Locale.current.measurementSystem`) contradice al del fichero, **gana el dispositivo**: el
idioma no dice el sistema de medida —hay hispanohablantes en Estados Unidos y angloparlantes en
España— y el ajuste del teléfono sí es una elección del usuario. El fichero sólo aporta el punto
de partida para cuando no hay nada mejor.

`unitFollows` y `defaultFollows` (en `weight_goal` → `weight_current`) hacen que el objetivo de
peso abra en la misma unidad y cerca del valor que el usuario acaba de introducir. Quien pesa en
libras no quiere elegir libras dos veces.

### `allowsCustom`

```json
"allowsCustom": { "enabled": true, "label": "Añadir otro", "placeholder": "Ej. Berenjena",
                  "maxItems": 10, "maxLength": 40 }
```

Convierte un `multi_choice` en «lista predefinida + lo que el usuario escriba», que es lo que
piden *alimentos que no me gustan* y *otras alergias*. Los valores libres viajan aparte, en
`customValues`, **nunca mezclados con `optionIds`**: un id es un dato estable con el que el
backend puede razonar, y un texto libre es una cadena que un humano tendrá que leer.

**Escribir un valor libre deselecciona la opción `exclusive`.** Es el mismo principio que marcar
cualquier otra opción: quien añade «Berenjena» ya no «come de todo».

Reglas al aceptar un valor libre: recortar espacios, colapsar espacios internos, rechazar saltos
de línea, cortar a `maxLength`, descartar el duplicado si ya coincide sin distinguir mayúsculas
con otro valor libre **o con el `title` de una opción existente** — quien escribe «brocoli»
teniendo «Brócoli» en la lista debe acabar con la opción, no con un duplicado.

---

## 4. Condicionales

```json
"visibleIf": { "all": [ { "questionId": "has_allergies", "operator": "equals", "value": "yes" } ] }
```

Operadores: `equals`, `notEquals`, `contains`, `notContains` (para `multi_choice`), `answered`,
`notAnswered`. `all` exige que se cumplan todas; `any` es la alternativa. Sin anidamiento: si un
caso lo necesita, se resuelve con una pregunta intermedia, que además es más legible para quien
edite el contenido.

Una pregunta oculta **no existe**: no se muestra, no cuenta para el progreso y no aparece en el
envío.

---

## 5. `crossChecks`

Avisos que dependen de otra respuesta. `weight_goal` los usa: si el objetivo es perder peso y el
peso objetivo es mayor que el actual, algo no cuadra.

```json
{ "severity": "warning", "rule": "lessThan", "compareTo": "weight_current",
  "when": { "all": [ { "questionId": "goal_primary", "operator": "equals", "value": "lose_weight" } ] },
  "message": "Has elegido perder peso, pero tu objetivo es mayor que tu peso actual. ¿Quieres revisarlo?" }
```

`severity: "warning"` **no bloquea**. Muestra el mensaje con dos salidas: «Revisar» (vuelve a la
pregunta citada en `when`) y «Continuar igualmente». `severity: "error"` sí bloquea, y hoy no lo
usa ninguna pregunta. Un usuario que insiste suele saber algo que el cuestionario no.

---

## 6. Estado, retroceso y edición

**La única fuente de verdad es el diccionario `answers`.** La transcripción del chat es una
proyección de `answers` sobre la lista de preguntas, y se recalcula entera. No hay un array de
burbujas al que se le hace `append`; si lo hay, retroceder deja de ser correcto en cuanto
aparece la primera condicional.

Definiciones:

- **Lista visible** = preguntas cuyo `visibleIf` se cumple con los `answers` actuales, en orden
  de declaración.
- **Pregunta actual** = la primera de la lista visible sin respuesta.

### Al editar la respuesta de una pregunta `Q`

1. Se escribe la respuesta nueva de `Q`.
2. Se recalcula la visibilidad de **todas** las preguntas posteriores a `Q`:
   - pasó de visible a oculta → **se borra su respuesta** (y se guarda en el almacén sombra, ver
     abajo);
   - pasó de oculta a visible → queda sin responder;
   - sigue visible → **su respuesta se conserva**.
3. La pregunta actual pasa a ser la primera visible sin respuesta. Si no hay ninguna, se vuelve
   al resumen.

**El paso 2 no borra las respuestas posteriores por el hecho de ser posteriores.** Truncar el
hilo es la implementación de una tarde y castiga al usuario que retrocede ocho preguntas para
corregir su altura obligándole a repetir las otras siete. Solo desaparece lo que la respuesta
nueva ha invalidado de verdad.

### Almacén sombra

Las respuestas borradas en el paso 2 se guardan aparte, indexadas por `questionId`. Si la
pregunta vuelve a ser visible, se restauran. El caso real: el usuario marca «Sí» a alergias,
teclea cuatro, se arrepiente, marca «No», vuelve a «Sí» — y sus cuatro alergias siguen ahí.

El almacén sombra **nunca se envía** y se descarta al completar el onboarding.

### Cómo se retrocede

Cada respuesta ya dada es un elemento tocable del hilo. Al tocarla se reabre su control en el
sitio, con el valor actual precargado. No hay botón «atrás»: en un chat, la respuesta anterior
ya está en pantalla y es el objetivo natural.

### Progreso

Se cuenta **por secciones** (`countsTowardProgress`), no por preguntas. Con condicionales, el
total de preguntas cambia según lo que el usuario responde, y una barra que retrocede o un «12
de 19» que pasa a «12 de 17» se lee como un fallo.

### Persistencia

`answers` se guarda en disco después de **cada** respuesta, junto a `onboardingId`,
`contentVersion` y `sessionId`. Si la app muere a mitad, se reanuda en la pregunta actual.

---

## 7. Versiones, caché y respaldo

- La app trae una copia del cuestionario **en el bundle**. Es la que se usa en el primer
  arranque sin red. Sin ella, un usuario sin cobertura no puede ni empezar.
- La última respuesta buena del servidor se cachea y tiene prioridad sobre la del bundle.
- **El cuestionario no cambia a mitad de sesión.** Quien empezó con `contentVersion: 3` la
  termina con la 3, aunque el servidor ya sirva la 4. Cambiar las preguntas bajo los pies del
  usuario invalida respuestas ya dadas y no hay forma correcta de resolverlo en caliente.
- Si `schemaVersion` es **mayor** que la que la app entiende, se usa la copia del bundle y se
  registra el hecho. Nunca se ignora en silencio una pregunta de tipo desconocido: si es
  obligatoria, saltársela produce un plan calculado con datos que faltan.
- `contentVersion` viaja en el envío. Es lo que permite al backend interpretar un `optionId` de
  hace tres meses.

---

## 7.1 Idiomas

Un fichero por idioma, **con los mismos ids en el mismo orden**. Lo que cambia entre ellos es
sólo texto, más `locale` y los `defaultUnit`. Todo lo demás —rangos, pasos, factores de
conversión, condiciones— es idéntico por construcción.

`python3 validate.py` sin argumentos valida todos los `questionnaire.*.json` y además compara sus
estructuras: falla si a una traducción le falta una opción, le sobra una burbuja o alguien
cambió un `type`. Es el error que aparece al traducir, y no lo detecta ningún JSON Schema porque
cada fichero es válido por separado.

**Un número dentro de un `description` no es el número que usa el backend.** «0,5 kg por semana»
y «About 1 lb a week» son el mismo `optionId` `steady` y el mismo déficit, aunque redondeen
distinto. El texto orienta al usuario; el valor lo decide el servidor a partir del id. Escribir
una cifra exacta en un idioma y otra en otro no crea una incoherencia — creerse la cifra del
texto, sí.

Si el servidor no tiene el idioma pedido, responde en `es` y lo declara en `locale`. La app
muestra lo que llegue: media traducción es peor que un idioma coherente que no es el preferido.

---

## 8. Envío

Una sola petición al terminar, no una por respuesta. Ver `answers-v1.example.json`.

```
POST {BASE_URL}/api/v1/kalorias/onboarding
Content-Type: application/json
Idempotency-Key: <sessionId>
```

| Regla | Motivo |
|---|---|
| Las respuestas viajan como **ids**, nunca como el texto de la opción | El texto cambia con cada retoque de copy y con el idioma |
| `measure` envía `value` en la **unidad canónica**, más `displayUnit` | Un número sin unidad fija es una bomba de relojería; `displayUnit` es solo para volver a mostrárselo como él lo eligió |
| Las preguntas ocultas **no aparecen** | Ni con `null` ni con `skipped`. No se preguntaron |
| Las opcionales no respondidas van con `skipped: true` | Distinto de «no se preguntó» |
| `customValues` separado de `optionIds` | §3 |
| `sessionId` es un UUID del cliente, reutilizado en cada reintento | Un reenvío tras un timeout no debe crear dos planes |

El envío es **health data** según el RGPD (condiciones de salud, embarazo, peso). Implica base
legal explícita, minimización y borrado, y que estos campos no acaben en logs ni en analítica de
producto. Merece una decisión consciente antes de implementar, no después.

---

## 9. Lo fácil de romper

1. **`optionId` no es único globalmente, solo dentro de su pregunta.** `yes` aparece en
   `wants_meal_plan`, `health_conditions_any` y `has_allergies`. La clave es siempre el par
   (`questionId`, `optionId`).
2. **`single_choice` avanza al tocar; `multi_choice` necesita confirmar.** Poner botón de
   confirmar en la única opción añade un toque a cada pregunta del cuestionario.
3. **La opción `exclusive` no es una opción normal.** Sin tratarla, se guardan combinaciones
   contradictorias.
4. **Cambiar de unidad no reescribe el valor canónico.**
5. **Editar hacia atrás no trunca el hilo**, solo poda lo que quedó invalidado.
6. **Una pregunta de `onboarding` no puede depender de una de `profile`.** No se habrá
   respondido, así que nunca aparece. No falla nada: simplemente no se pregunta.
7. **Las cifras dentro de un `description` redondean distinto en cada idioma**, a propósito. El
   déficit sale del `optionId`, nunca del texto.
8. **Un `emoji` es texto**, y VoiceOver lo lee. El `title` va antes que el emoji en el orden de
   lectura, y el emoji se marca como decorativo cuando el `title` ya lo dice todo (Principio VI
   de la constitución).

---

## 10. Decisiones de contenido

Sobre lo pedido en el brief original, esto es lo que se añadió y por qué.

| Pregunta | Por qué |
|---|---|
| `goal_pace_loss` / `goal_pace_gain` | **La más importante.** El déficit calórico sale del ritmo. Sin preguntarlo hay que inventarse un número y el plan no es de nadie. Sólo se muestra una de las dos |
| `meal_count`, `cooking_time` | Se pregunta si quiere plan de alimentación, pero no cómo debe ser. Un plan de cinco comidas elaboradas para quien come dos veces y no cocina no dura una semana. Sólo se muestran si pidió plan |
| `birth_date` en vez de edad | Un plan calculado con la edad que el usuario tenía al registrarse envejece mal. La conversión a edad es trivial; la inversa no existe |
| `health_disclaimer` | Si el usuario declara diabetes o un TCA, la app debería decir algo antes de proponerle un déficit |
| `extra_notes` | Opcional, al final. Recoge lo que ninguna opción cubre y dice qué preguntas faltan en la v2 |
| `egg` en alergias | Es uno de los catorce alérgenos de declaración obligatoria y faltaba |
| `pregnancy` en salud | Cambia por completo el cálculo, y es lo que impide proponer un déficit a quien no debe |

### `disliked_foods` pasa al perfil

Es la única pregunta que se difiere, y por un criterio concreto: **no entra en el cálculo
calórico**. Afecta a qué comidas se sugieren, no a cuántas calorías tocan, así que el primer plan
sale igual de bueno sin ella y son doce opciones menos antes de ver resultado alguno.

### Las condiciones de salud NO pasan al perfil

Estaban propuestas como candidatas a diferir junto a `disliked_foods`, por longitud. **Se quedan
en el onboarding**, y el motivo lo da la propia lista: `pregnancy`, `eating_disorder`,
`diabetes_t1`. Diferirlas significa calcular el primer plan sin saberlo, y el primer plan es
justo el que el usuario va a seguir. Acortar el cuestionario no es razón suficiente para eso.

Queda entonces una asimetría deliberada: se difiere lo que sólo afecta al gusto y se pregunta
todo lo que afecta al número.

### `motivation_level` se queda, sabiendo lo que es

No alimenta ningún cálculo. Es un gesto de compromiso, y sí sube la tasa de finalización.
Conviene tenerlo escrito para que nadie lo busque en la fórmula, y es la primera candidata a caer
si hace falta acortar.

### `sex: "unspecified"` — decisión cerrada

Ofrecer «prefiero no decirlo» obliga a definir qué hace Mifflin-St Jeor sin sexo, porque la
fórmula tiene una constante distinta para cada uno (+5 y −161).

**Decisión: se usa la media de ambas, −78.** Es el punto medio y el error máximo queda en ±83
kcal/día, del orden de la imprecisión que ya tiene cualquier estimación de metabolismo basal. La
alternativa —quitar la opción— obliga a declarar el sexo para usar la app, y la otra
—preguntarlo después— deja el primer plan igual de estimado pero con una pregunta más.

Lo que **no** vale es dejarlo como un `else` sin escribir: quien lea el código dentro de un año
no puede distinguir una decisión de un olvido.

### Longitud

| Perfil de usuario | Preguntas | Burbujas info |
|---|---|---|
| Perder peso, quiere plan, con alergias y condiciones | 20 | 3 |
| Mantener peso, sin plan, sin alergias ni condiciones | 14 | 2 |

Las seis de diferencia son `weight_goal`, `goal_pace_loss`, `allergies`, `health_conditions`,
`meal_count` y `cooking_time`. El abandono se concentra a partir de la décima: catorce es
razonable, veinte es largo, y son las condicionales las que hacen que sólo llegue a veinte quien
de verdad tiene algo que contar. Si hay que
recortar más, el orden es `motivation_level`, `calorie_experience` (sirve para el tono de la
interfaz, no para el cálculo) y `extra_notes`.

### Los permisos de notificaciones no van aquí

Son un diálogo del sistema y se piden después del primer plan, cuando ya hay algo que notificar.
