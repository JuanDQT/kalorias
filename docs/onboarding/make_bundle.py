#!/usr/bin/env python3
"""Genera la copia de respaldo que viaja dentro de la app.

La app embarca el cuestionario para que un primer arranque sin cobertura no se
quede bloqueado. Esa copia tiene que ser **exactamente lo que el servidor
respondería**, no el fichero fuente: filtrada por `stage`, sin ese campo y con
el sobre `data`. Generarla en vez de mantenerla a mano es lo que evita que la
app de respaldo y el servidor acaben contestando cosas distintas.

    python3 make_bundle.py [stage]        # por defecto, onboarding
"""

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).parent
DEST = HERE.parent.parent / "Kalorias" / "Resources" / "Onboarding"


def build(doc: dict, stage: str) -> dict:
    sections = []
    for section in doc["sections"]:
        questions = [q for q in section["questions"] if q.pop("stage", None) == stage]
        if questions:
            sections.append({**section, "questions": questions})
    return {"data": {**doc, "sections": sections}}


def main() -> int:
    stage = sys.argv[1] if len(sys.argv) > 1 else "onboarding"
    DEST.mkdir(parents=True, exist_ok=True)

    for source in sorted(HERE.glob("questionnaire.*.json")):
        if source.name == "questionnaire.schema.json":
            continue
        locale = source.stem.split(".")[-1]
        payload = build(json.load(open(source, encoding="utf-8")), stage)
        out = DEST / f"onboarding.{locale}.json"
        with open(out, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
            f.write("\n")
        n = sum(len(s["questions"]) for s in payload["data"]["sections"])
        print(f"{out.relative_to(HERE.parent.parent)}  ·  {n} elementos, locale {locale}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
