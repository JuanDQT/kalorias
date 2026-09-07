#!/usr/bin/env python3
"""Valida el fichero fuente del cuestionario.

Sólo biblioteca estándar. Si `jsonschema` está instalado también aplica
questionnaire.schema.json; si no, avisa y sigue con el resto.

Lo que comprueba aquí es lo que un JSON Schema no puede expresar: referencias
entre preguntas y, sobre todo, su **orden**. Una condición que apunta a una
pregunta posterior no falla al validar el JSON, falla en producción, en el
dispositivo de un usuario, como una pregunta que no aparece nunca.

    python3 validate.py [fichero...]      # sin argumentos: todos los idiomas

Con más de un fichero valida cada uno y además compara sus estructuras: es la
comprobación que hace falta al traducir, donde lo que se rompe no es el JSON
sino la correspondencia de ids entre idiomas.

Salida 0 si todo correcto, 1 si hay errores. Los avisos no rompen la salida.
"""

import glob
import json
import re
import sys
from datetime import date, timedelta

SCHEMA_FILE = "questionnaire.schema.json"
CHOICE_TYPES = {"single_choice", "multi_choice"}
NUMERIC_TYPES = {"measure", "number"}
STAGES = ("onboarding", "profile")

errors: list[str] = []
warnings: list[str] = []


def err(qid: str, msg: str) -> None:
    errors.append(f"{qid}: {msg}")


def warn(qid: str, msg: str) -> None:
    warnings.append(f"{qid}: {msg}")


def resolve_date(token: str) -> date:
    """ISO-8601 o token relativo (`today`, `today-16y`, `today+30d`)."""
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", token):
        return date.fromisoformat(token)
    m = re.fullmatch(r"today(?:([+-])(\d+)([dmy]))?", token)
    if not m:
        raise ValueError(f"token de fecha no reconocido: {token!r}")
    today = date.today()
    if not m.group(1):
        return today
    sign = 1 if m.group(1) == "+" else -1
    n = int(m.group(2)) * sign
    unit = m.group(3)
    if unit == "d":
        return today + timedelta(days=n)
    # Aproximación deliberada: sólo se usa para comparar límites entre sí, no
    # para mostrar nada. El dispositivo resuelve el token con su calendario.
    return today + timedelta(days=n * (30 if unit == "m" else 365))


def on_step(value: float, lo: float, step: float) -> bool:
    steps = (value - lo) / step
    return abs(steps - round(steps)) < 1e-6


def skeleton(doc: dict) -> dict:
    """Ids y tipos, sin nada traducible. Dos idiomas deben producir lo mismo."""
    return {
        "sections": [
            {
                "id": s.get("id"),
                "questions": [
                    {
                        "id": q.get("id"),
                        "stage": q.get("stage"),
                        "type": q.get("type"),
                        "prompts": len(q.get("prompt", [])),
                        "options": [o.get("id") for o in q.get("options", [])],
                    }
                    for q in s.get("questions", [])
                ],
            }
            for s in doc.get("sections", [])
        ]
    }


def main(path: str) -> int:
    doc = json.load(open(path, encoding="utf-8"))

    try:
        import jsonschema  # noqa: PLC0415
    except ImportError:
        warnings.append(
            "(schema) `jsonschema` no instalado: no se ha aplicado questionnaire.schema.json. "
            "`pip install jsonschema` para la validación completa"
        )
    else:
        schema = json.load(open(SCHEMA_FILE, encoding="utf-8"))
        v = jsonschema.Draft202012Validator(schema)
        for e in sorted(v.iter_errors(doc), key=lambda e: list(e.path)):
            errors.append("/" + "/".join(str(p) for p in e.path) + ": " + e.message)

    # Lista plana en orden de declaración: el orden ES el contrato.
    flat = [q for s in doc.get("sections", []) for q in s.get("questions", [])]
    position = {}
    for i, q in enumerate(flat):
        qid = q.get("id")
        if qid in position:
            err(qid, "id repetido; los ids son únicos en TODO el cuestionario, no por sección")
        position.setdefault(qid, i)
    by_id = {q.get("id"): q for q in flat}

    def check_reference(q, i, ref, field):
        """La referencia existe y está declarada antes. Devuelve la pregunta o None."""
        qid = q["id"]
        if ref not in by_id:
            err(qid, f"{field} apunta a `{ref}`, que no existe")
            return None
        if position[ref] >= i:
            err(qid, f"{field} apunta a `{ref}`, declarada después: nunca se cumplirá")
            return None
        if by_id[ref].get("stage") != q.get("stage") and q.get("stage") == "onboarding":
            err(qid, f"{field} apunta a `{ref}`, que está en stage `profile`: no se habrá respondido")
        return by_id[ref]

    for i, q in enumerate(flat):
        qid = q.get("id", f"<sin id, posición {i}>")
        qtype = q.get("type")
        options = q.get("options", [])

        if q.get("stage") not in STAGES:
            err(qid, f"stage debe ser uno de {STAGES}")

        # --- Opciones ---
        seen_ids, seen_titles = set(), {}
        for o in options:
            oid = o.get("id")
            if oid in seen_ids:
                err(qid, f"opción `{oid}` repetida")
            seen_ids.add(oid)
            title = o.get("title", "").strip().casefold()
            if title in seen_titles:
                err(qid, f"dos opciones con el mismo título: `{seen_titles[title]}` y `{oid}`")
            seen_titles[title] = oid
            if o.get("exclusive") and qtype != "multi_choice":
                err(qid, f"`exclusive` en `{oid}` sólo tiene sentido en multi_choice")
            emoji = o.get("emoji")
            # Basta con exigir que no sea ASCII: cubre tanto "OK" como ":)", que es
            # como se cuela un emoticono de teclado donde debería ir un emoji.
            if emoji and emoji.isascii():
                err(qid, f"`emoji` de `{oid}` es ASCII: {emoji!r}. Debe ser un emoji Unicode")

        exclusives = [o["id"] for o in options if o.get("exclusive")]
        if len(exclusives) > 1:
            warn(qid, f"más de una opción exclusive ({', '.join(exclusives)}): sólo una puede ganar")

        # --- Validación de selección ---
        val = q.get("validation", {})
        lo, hi = val.get("minSelections"), val.get("maxSelections")
        if lo is not None and options and lo > len(options):
            err(qid, f"minSelections {lo} > {len(options)} opciones: imposible de satisfacer")
        if lo is not None and hi is not None and hi < lo:
            err(qid, f"maxSelections {hi} < minSelections {lo}")
        if qtype == "multi_choice" and q.get("required", True) and lo in (None, 0):
            warn(qid, "multi_choice obligatoria sin minSelections: se puede confirmar sin marcar nada")

        # --- visibleIf ---
        group = q.get("visibleIf") or {}
        for cond in group.get("all", []) + group.get("any", []):
            ref_q = check_reference(q, i, cond.get("questionId"), "visibleIf")
            if ref_q is None:
                continue
            value = cond.get("value")
            if value is None:
                continue
            if ref_q.get("type") not in CHOICE_TYPES:
                err(qid, f"visibleIf compara con `{ref_q['id']}`, que es {ref_q.get('type')} y no tiene opciones")
            elif value not in {o.get("id") for o in ref_q.get("options", [])}:
                err(qid, f"visibleIf espera `{value}`, que no es una opción de `{ref_q['id']}`")
            op = cond.get("operator")
            if op in ("contains", "notContains") and ref_q.get("type") != "multi_choice":
                err(qid, f"`{op}` sobre `{ref_q['id']}`, que es single_choice: usa equals/notEquals")
            if op in ("equals", "notEquals") and ref_q.get("type") == "multi_choice":
                err(qid, f"`{op}` sobre `{ref_q['id']}`, que es multi_choice: usa contains/notContains")

        # --- crossChecks ---
        for cc in q.get("crossChecks", []):
            ref_q = check_reference(q, i, cc.get("compareTo"), "crossChecks.compareTo")
            if ref_q is not None:
                if ref_q.get("type") not in NUMERIC_TYPES:
                    err(qid, f"crossChecks compara con `{ref_q['id']}`, que no es numérica")
                elif qtype == "measure" and ref_q.get("type") == "measure":
                    a = q.get("measure", {}).get("canonicalUnit")
                    b = ref_q.get("measure", {}).get("canonicalUnit")
                    if a != b:
                        err(qid, f"crossChecks compara {a} con {b}: unidades canónicas distintas")
            for cond in (cc.get("when") or {}).get("all", []) + (cc.get("when") or {}).get("any", []):
                check_reference(q, i, cond.get("questionId"), "crossChecks.when")

        # --- measure ---
        m = q.get("measure")
        if m:
            unit_ids = {u["id"] for u in m.get("units", [])}
            if m.get("defaultUnit") not in unit_ids:
                err(qid, f"defaultUnit `{m.get('defaultUnit')}` no está entre las unidades")
            canonical = [u for u in m.get("units", []) if u["id"] == m.get("canonicalUnit")]
            if not canonical:
                err(qid, f"canonicalUnit `{m.get('canonicalUnit')}` no está entre las unidades")
            else:
                comps = canonical[0]["components"]
                if len(comps) != 1 or abs(comps[0]["toCanonical"] - 1) > 1e-9:
                    err(qid, "la unidad canónica debe tener un solo componente con toCanonical = 1")

            for u in m.get("units", []):
                for c in u.get("components", []):
                    tag = f"{u['id']}.{c['id']}"
                    if c["min"] >= c["max"]:
                        err(qid, f"{tag}: min >= max")
                    if not (c["min"] <= c["default"] <= c["max"]):
                        err(qid, f"{tag}: default {c['default']} fuera de [{c['min']}, {c['max']}]")
                    elif not on_step(c["default"], c["min"], c["step"]):
                        err(qid, f"{tag}: default {c['default']} no cae en un múltiplo de step {c['step']}")
                    dec = len(str(c["step"]).split(".")[1]) if "." in str(c["step"]) else 0
                    if dec > c["decimals"]:
                        err(qid, f"{tag}: step {c['step']} necesita decimals >= {dec}, hay {c['decimals']}")

            # Rangos coherentes entre unidades: si en kg se puede llegar a 250 y en
            # lb sólo a 200 kg, el mismo usuario cabe o no según la unidad que toque.
            spans = {}
            for u in m.get("units", []):
                lo_c = sum(c["min"] * c["toCanonical"] for c in u["components"])
                hi_c = sum(c["max"] * c["toCanonical"] for c in u["components"])
                spans[u["id"]] = (lo_c, hi_c)
            if spans:
                los = [s[0] for s in spans.values()]
                his = [s[1] for s in spans.values()]
                width = max(his) - min(los)
                drift = max(max(los) - min(los), max(his) - min(his)) / width if width else 0
                if drift > 0.02:
                    detail = ", ".join(f"{k} = {v[0]:.1f}–{v[1]:.1f}" for k, v in spans.items())
                    msg = ("los rangos de las unidades no cubren lo mismo al convertirlos "
                           f"({drift:.0%} de desfase): {detail}")
                    # Un desfase grande casi siempre es un `toCanonical` equivocado, no
                    # un redondeo: el mismo usuario cabría o no según la unidad que elija.
                    (err if drift > 0.05 else warn)(qid, msg)

            for field in ("unitFollows", "defaultFollows"):
                ref = m.get(field)
                if not ref:
                    continue
                ref_q = check_reference(q, i, ref, f"measure.{field}")
                if ref_q is None:
                    continue
                ref_m = ref_q.get("measure")
                if not ref_m:
                    err(qid, f"{field} apunta a `{ref}`, que no es measure")
                elif {u["id"] for u in ref_m["units"]} != unit_ids:
                    err(qid, f"{field} apunta a `{ref}`, con otro juego de unidades: no se puede heredar")

        # --- date ---
        d = q.get("date")
        if d:
            try:
                lo_d, hi_d = resolve_date(d["minDate"]), resolve_date(d["maxDate"])
                if lo_d >= hi_d:
                    err(qid, f"minDate {d['minDate']} no es anterior a maxDate {d['maxDate']}")
                if "default" in d:
                    def_d = resolve_date(d["default"])
                    if not (lo_d <= def_d <= hi_d):
                        err(qid, f"default {d['default']} fuera del rango")
            except ValueError as e:
                err(qid, str(e))

        # --- coherencia general ---
        if qtype == "info" and q.get("required") is False:
            warn(qid, "`info` no es una pregunta: `required: false` no significa nada")
        if not q.get("required", True) and "skipLabel" not in q:
            warn(qid, "opcional pero sin `skipLabel`: el usuario no ve cómo saltarla")

    # --- Alcanzabilidad de las opciones referenciadas ---
    referenced = set()
    for q in flat:
        for cond in (q.get("visibleIf") or {}).get("all", []) + (q.get("visibleIf") or {}).get("any", []):
            referenced.add((cond.get("questionId"), cond.get("value")))
    for q in flat:
        if q.get("type") != "single_choice":
            continue
        gate = {o["id"] for o in q.get("options", [])}
        used = {v for (qq, v) in referenced if qq == q["id"]}
        if used and len(gate) == 2 and len(used) == 1:
            continue  # puerta sí/no: referenciar sólo una rama es lo normal

    n_onb = sum(1 for q in flat if q.get("stage") == "onboarding" and q.get("type") != "info")
    n_prof = sum(1 for q in flat if q.get("stage") == "profile" and q.get("type") != "info")

    for w in warnings:
        print(f"aviso   {w}")
    for e in errors:
        print(f"ERROR   {e}")

    print(f"\n{len(flat)} elementos · {n_onb} preguntas en onboarding · {n_prof} en perfil "
          f"· contentVersion {doc.get('contentVersion')}")
    print("FALLA" if errors else "OK")
    return 1 if errors else 0


def compare(paths: list[str]) -> int:
    """Todos los idiomas describen el mismo cuestionario, o no son el mismo cuestionario."""
    base_path, *rest = paths
    base = skeleton(json.load(open(base_path, encoding="utf-8")))
    failed = 0
    for p in rest:
        other = skeleton(json.load(open(p, encoding="utf-8")))
        if other == base:
            print(f"OK      {p} coincide con {base_path}")
            continue
        failed = 1
        b = {q["id"]: q for s in base["sections"] for q in s["questions"]}
        o = {q["id"]: q for s in other["sections"] for q in s["questions"]}
        for qid in sorted(set(b) - set(o)):
            print(f"ERROR   {p}: falta la pregunta `{qid}`")
        for qid in sorted(set(o) - set(b)):
            print(f"ERROR   {p}: sobra la pregunta `{qid}`, no está en {base_path}")
        for qid in sorted(set(b) & set(o)):
            if b[qid] == o[qid]:
                continue
            if b[qid]["options"] != o[qid]["options"]:
                print(f"ERROR   {p}: `{qid}` no tiene las mismas opciones "
                      f"({b[qid]['options']} vs {o[qid]['options']})")
            if b[qid]["prompts"] != o[qid]["prompts"]:
                print(f"ERROR   {p}: `{qid}` tiene {o[qid]['prompts']} burbujas "
                      f"y en {base_path} tiene {b[qid]['prompts']}")
            for f in ("stage", "type"):
                if b[qid][f] != o[qid][f]:
                    print(f"ERROR   {p}: `{qid}` cambia `{f}`: {o[qid][f]} vs {b[qid][f]}")
    return failed


if __name__ == "__main__":
    # `questionnaire.*.json` también casa con el propio esquema, que no es un cuestionario.
    args = sys.argv[1:] or [f for f in sorted(glob.glob("questionnaire.*.json"))
                            if f != SCHEMA_FILE]
    status = 0
    for a in args:
        print(f"--- {a}")
        status |= main(a)
    if len(args) > 1:
        print("--- estructura entre idiomas")
        status |= compare(args)
    sys.exit(status)
