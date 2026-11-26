"""Reuse the project's existing translated catalogs in the Qt shell.

New Qt-only text falls back to English until translated; coverage is reported,
never filled with invented translations. Generated TS files belong in the build.
"""
import argparse
import json
import re
from pathlib import Path
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[2]

def languages():
    return [line.split("\t") for line in (REPO / "i18n/languages.tsv").read_text(encoding="utf-8").splitlines()
            if line and not line.startswith("#")]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    messages = set()
    for path in (REPO / "qt-ui/qml").glob("*.qml"):
        text = path.read_text(encoding="utf-8")
        for source in re.findall(r'qsTr\(("(?:[^"\\]|\\.)*")', text):
            messages.add((path.stem, json.loads(source)))
        for context, source in re.findall(r'qsTranslate\(("(?:[^"\\]|\\.)*"),\s*("(?:[^"\\]|\\.)*")', text):
            messages.add((json.loads(context), json.loads(source)))
    for path in (REPO / "qt-ui/src").glob("*.cpp"):
        for source in re.findall(r'\btr\(("(?:[^"\\]|\\.)*")', path.read_text(encoding="utf-8")):
            messages.add((path.stem, json.loads(source)))
    dedicated = {}
    for path in (REPO / "qt-ui/i18n").glob("*.ts"):
        code = path.stem.removeprefix("auralis_").replace("zh_CN", "zh-hans")
        entries = {}
        for context in ET.parse(path).getroot().findall("context"):
            for message in context.findall("message"):
                source = message.findtext("source") or ""
                key = (context.findtext("name") or "", source)
                messages.add(key)
                translation = message.find("translation")
                if translation is not None and translation.get("type") != "unfinished" and translation.text:
                    entries[key] = translation.text
        dedicated[code] = entries
    coverage = {}
    for code, *_ in languages():
        source_code = "en" if code == "en-gb" else code
        catalog = {}
        path = REPO / "i18n" / f"{source_code}.tsv"
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith("#"): continue
            fields = line.split("\t")
            if len(fields) == 3 and not fields[0].startswith("@"):
                catalog[fields[1]] = fields[2]
        root = ET.Element("TS", version="2.1", language=code.replace("-", "_"), sourcelanguage="en")
        translated = 0
        for name in sorted({key[0] for key in messages}):
            context = ET.SubElement(root, "context")
            ET.SubElement(context, "name").text = name
            for key in sorted(key for key in messages if key[0] == name):
                source = key[1]
                value = dedicated.get(source_code, {}).get(key) or catalog.get(source)
                message = ET.SubElement(context, "message")
                ET.SubElement(message, "source").text = source
                translation = ET.SubElement(message, "translation")
                if value:
                    translation.text = value
                    translated += int(value != source or source_code == "en")
                else:
                    translation.set("type", "unfinished")
                    translation.text = source
        ET.indent(root)
        ET.ElementTree(root).write(args.output / f"auralis_{code}.ts", encoding="utf-8", xml_declaration=True)
        coverage[code] = {"translated": translated, "total": len(messages)}
    (args.output / "coverage.json").write_text(json.dumps(coverage, indent=2), encoding="utf-8")
    print(f"Generated {len(coverage)} Qt locale catalogs; coverage.json records English fallbacks.")

if __name__ == "__main__":
    main()
