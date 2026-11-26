"""Build NSIS language resources from official NSIS packs and existing catalogs.

Official translations are retained where available. Missing strings use English
and are counted in the report, rather than mislabelled as complete translations.
"""
import argparse
import json
import locale
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--nsis", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    official = args.nsis / "Contrib/Language files"
    packs = {}
    for path in official.glob("*.nlf"):
        text = path.read_text(encoding="utf-8-sig")
        values = [line for line in text.splitlines() if line and not line.startswith("#")]
        packs[int(values[1])] = path
    ids = {name.replace("_", "-").lower(): value for value, name in locale.windows_locale.items()}
    macros, report = [], {}
    rows = [line.split("\t") for line in (REPO / "i18n/languages.tsv").read_text(encoding="utf-8").splitlines()
            if line and not line.startswith("#")]
    english = (official / "English.nlf").read_text(encoding="utf-8-sig")
    used = set()
    for index, (code, name, native, flag, inno, windows) in enumerate(rows):
        langid = ids.get(windows.lower())
        isl = REPO / "tools/installer/languages" / f"{code}.isl"
        inno_text = isl.read_text(encoding="utf-8-sig") if isl.exists() else ""
        match = re.search(r"LanguageID=\$([0-9A-Fa-f]+)", inno_text)
        if match: langid = int(match[1], 16)
        if langid is None: raise ValueError(f"No Windows language ID for {code} / {windows}")
        if langid in used: raise ValueError(f"Duplicate installer language ID for {code}")
        used.add(langid)
        pack = packs.get(langid)
        template = pack or official / "English.nlf"
        nlf = template.read_text(encoding="utf-8-sig")
        nlf = re.sub(r"(# Language ID\s*\n)\d+", lambda m: m[1]+str(langid), nlf, count=1)
        translations = {}
        catalog = REPO / "i18n" / f"{'en' if code == 'en-gb' else code}.tsv"
        for line in catalog.read_text(encoding="utf-8").splitlines():
            fields = line.split("\t")
            if len(fields) == 3 and not fields[0].startswith(("#", "@")):
                translations[fields[1]] = fields[2]
        if not pack:
            # Translate exact known labels; keep NSIS variable-bearing sentences intact.
            nlf = "\n".join(translations.get(line, line) if not line.startswith("#") else line for line in nlf.splitlines())+"\n"
        identifier = "Auralis_"+code.replace("-", "_")
        nsh = template.with_suffix(".nsh").read_text(encoding="utf-8-sig")
        replacement = f'!insertmacro LANGFILE "{identifier}" "{name}" "{native}" "{name}"'
        nsh = re.sub(r'!insertmacro LANGFILE\s+[^\n]+', lambda _: replacement, nsh, count=1)
        (args.output / f"{identifier}.nlf").write_text(nlf, encoding="utf-8-sig")
        (args.output / f"{identifier}.nsh").write_text(nsh, encoding="utf-8-sig")
        macros += [f'!define LANG_{identifier} {langid}', f'!define LANG_{identifier}_CP 0',
                   f'!insertmacro MUI_LANGUAGEEX "${{AURALIS_LANGUAGE_DIR}}" "{identifier}"']
        report[code] = {"official_nsis_pack": bool(pack), "english_fallback": not bool(pack)}
    (args.output / "languages.nsh").write_text("\n".join(macros)+"\n", encoding="utf-8-sig")
    (args.output / "coverage.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Generated {len(report)} installer locale choices; see coverage.json for fallback locales.")

if __name__ == "__main__":
    main()
