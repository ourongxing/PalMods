"""Create local Workshop packages from existing builds; never install or upload."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tempfile
import zipfile

from palmods import ROOT, MODS_ROOT, BUILD_ROOT, DIST_ROOT, PALCOMBO_BUILD

MODS = ('BetterWorkbench', 'PalCombo', 'UpdraftElevator', 'PointBlankBurstSkills', 'BetterBulkStorage', 'BetterStorage', 'AnywherePalBox', 'BetterPalSouls', 'ExtraImplantDrops', 'QuickButcher')
LANGUAGES = ('zh-Hans', 'zh-Hant', 'ja', 'en')
TEMPLATES_ROOT = ROOT / 'tools/workshop/templates'


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def steam_format_markdown(text):
    """Convert the headings, flat lists and inline markup used by our READMEs."""
    def inline(value):
        def replace(match):
            code, bold, label, url = match.groups()
            if code is not None:
                return '[b][noparse]' + code + '[/noparse][/b]'
            if bold is not None:
                return '[b]' + bold + '[/b]'
            return '[url=' + url + ']' + label + '[/url]'
        return re.sub(r'`([^`\n]+)`|\*\*([^*\n]+)\*\*|\[([^]\n]+)\]\(([^)\n]+)\)', replace, value)

    output, list_type = [], None
    for line in text.strip().splitlines():
        bullet = re.fullmatch(r'[-*] (.+)', line)
        ordered = re.fullmatch(r'\d+\. (.+)', line)
        next_type = 'list' if bullet else 'olist' if ordered else None
        if list_type and next_type != list_type:
            output.append('[/' + list_type + ']')
            list_type = None
        if next_type:
            if not list_type:
                list_type = next_type
                output.append('[' + list_type + ']')
            output.append('[*]' + inline((bullet or ordered).group(1)))
        else:
            heading = re.fullmatch(r'(#{1,6})\s+(.+)', line)
            if heading:
                tag = 'h' + str(min(len(heading.group(1)), 3))
                output.append('[' + tag + ']' + inline(heading.group(2)) + '[/' + tag + ']')
            else:
                output.append(inline(line))
    if list_type:
        output.append('[/' + list_type + ']')
    return '\n'.join(output)


def common_footer(folder, language):
    """One localized support/source template; add logs only for UE4SS mods."""
    metadata = folder / 'Info.json'
    dependencies = (read_json(metadata).get('Dependencies') or []) if metadata.exists() else []
    logs = ''
    if 'UE4SSExperimentalPW' in dependencies:
        logs = (TEMPLATES_ROOT / f'UE4SS.{language}.md').read_text(encoding='utf-8-sig').strip() + '\n\n'
    template = (TEMPLATES_ROOT / f'README.{language}.md').read_text(encoding='utf-8-sig')
    return template.replace('{{runtime_logs}}', logs).strip()


def append_footer(content, footer):
    content = content.strip()
    # Package READMEs already include the footer when validate() regenerates listings.
    return content + '\n' if content.endswith(footer) else content + '\n\n' + footer + '\n'


def render_readme(folder, language):
    path = folder / f'README.{language}.md'
    content = path.read_text(encoding='utf-8-sig').strip()
    sections = re.split(r'\n\s*\n', content, maxsplit=2)
    if (len(sections) != 3 or not re.fullmatch(r'# [^\n]+', sections[0])
            or not re.fullmatch(r'\d+\.\d+\.\d+\S* · [^\n]+', sections[1])
            or not sections[2].strip()):
        raise ValueError(f'Expected title, version/author and body in {path}')
    return append_footer(content, common_footer(folder, language))


def generate_listings(folder):
    """Render localized mod READMEs with the shared support/source footer."""
    listings = {}
    for language in LANGUAGES:
        sections = re.split(r'\n\s*\n', render_readme(folder, language).strip(), maxsplit=2)
        # Steam descriptions use BBCode. Keep the version/author from the README.
        description = '[b]' + sections[1] + '[/b]\n\n' + steam_format_markdown(sections[2])
        listings[language] = {'Title': sections[0][2:].strip(), 'Description': description}
    return listings


def write_listings(folder, listings):
    (folder / 'listing.json').write_text(
        json.dumps(listings, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def payload(mod):
    """Explicit runtime inputs exclude local jobs, logs, SDKs and old mod names."""
    if mod == 'QuickButcher':
        folder = DIST_ROOT / mod
        pak = folder / 'QuickButcher_P.pak'
        report = read_json(folder / 'build-audit.json')
        if report.get('Mod') != mod or digest(pak) != report['PakSHA256']:
            raise ValueError('QuickButcher PAK differs from build audit; rebuild first')
        return [(pak, 'Paks/QuickButcher_P.pak')]
    source = MODS_ROOT / mod / 'mod'
    files = []
    if mod != 'PointBlankBurstSkills':
        files += [(p, p.relative_to(source).as_posix())
                  for p in sorted((source / 'Scripts').rglob('*.lua'))]
        files += [(None, 'enabled.txt')]
    if mod == 'BetterWorkbench':
        dll = BUILD_ROOT / mod / 'native/Release/BetterWorkbenchNative.dll'
        report = read_json(BUILD_ROOT / mod / 'import-audit.json')
        if digest(dll).lower() != report['bridge_sha256'].lower():
            raise ValueError('BetterWorkbench DLL differs from import audit; rebuild and audit first')
        if report['ue4ss_imports_verified'] < 46:
            raise ValueError('BetterWorkbench import audit is incomplete')
        files += [(dll, 'dlls/main.dll')]
    elif mod == 'PalCombo':
        files += [(source / 'config.ini', 'config.ini'),
                  (PALCOMBO_BUILD / 'Game__Shipping__Win64/bin/PalComboFillerNative.dll', 'dlls/main.dll')]
    elif mod == 'ExtraImplantDrops':
        dll = BUILD_ROOT / mod / 'Game__Shipping__Win64/bin/ExtraImplantDropsNative.dll'
        report = read_json(BUILD_ROOT / mod / 'import-audit.json')
        if digest(dll).lower() != report['dll_sha256'].lower():
            raise ValueError('ExtraImplantDrops DLL differs from import audit; rebuild and audit first')
        if report['imports_verified'] < 24:
            raise ValueError('ExtraImplantDrops import audit is incomplete')
        files += [(source / 'config.ini', 'config.ini'), (dll, 'dlls/main.dll')]
    elif mod == 'BetterBulkStorage':
        files += [(BUILD_ROOT / mod / 'native/Game__Shipping__Win64/bin/BetterBulkStorageNative.dll',
                   'dlls/main.dll')]
    elif mod == 'BetterStorage':
        files += [(BUILD_ROOT / mod / 'native/Game__Shipping__Win64/bin/BetterStorageNative.dll',
                   'dlls/main.dll')]
        schema = MODS_ROOT / mod / 'schema'
        files += [(p, 'PalSchema/' + p.relative_to(schema).as_posix())
                  for p in sorted(schema.rglob('*.json'))]
    elif mod == 'UpdraftElevator':
        schema = BUILD_ROOT / mod / 'stage/Mods/PalSchema/mods/UpdraftElevator'
        files += [(schema / 'buildings/wind_small.json', 'PalSchema/buildings/wind_small.json'),
                  (schema / 'paks/UpdraftElevator_P.pak', 'PalSchema/paks/UpdraftElevator_P.pak')]
        files += [(p, 'PalSchema/translations/' + p.relative_to(source / 'translations').as_posix())
                  for p in sorted((source / 'translations').rglob('*.json'))]
        # Use the generated helper so the Lua defaults match the packaged variants.
        helper = BUILD_ROOT / mod / 'stage/Mods/UpdraftElevator'
        files = [(helper / dest if dest.startswith('Scripts/') else src, dest) for src, dest in files]
    elif mod == 'PointBlankBurstSkills':
        files += [(source / 'raw/point_blank_burst_skills.json',
                   'PalSchema/raw/point_blank_burst_skills.json')]
    for src, dest in files:
        if src is not None:
            if not src.is_file():
                raise FileNotFoundError(f'Missing runtime input: {src}; run tools/build.py {mod}')
            if src.suffix == '.json':
                read_json(src)
    return files


def validate(package):
    """Validate metadata and every installation target before emitting a ZIP."""
    info = read_json(package / 'Info.json')
    if not re.fullmatch(r'[A-Za-z0-9]+', info['PackageName']):
        raise ValueError('PackageName must contain only ASCII letters and digits')
    for key in ('ModName', 'Author', 'Version'):
        if not isinstance(info[key], str) or not info[key].strip():
            raise ValueError(f'{key} must not be empty')
    if type(info['MinRevision']) is not int or info['MinRevision'] < 0:
        raise ValueError('MinRevision must be a nonnegative integer')
    if info['DebugMode'] is not False:
        raise ValueError('Release packages must use DebugMode=false')
    if not isinstance(info['Dependencies'], list) or not all(
            isinstance(dep, str) and re.fullmatch(r'[A-Za-z0-9]+', dep) for dep in info['Dependencies']):
        raise ValueError('Dependencies must be an array of package names')

    def target_path(target):
        relative = PurePosixPath(target)
        if '\\' in target or ':' in target or relative.is_absolute() or '..' in relative.parts:
            raise ValueError(f'Unsafe package path: {target}')
        result = package / relative
        if not result.resolve().is_relative_to(package.resolve()) or not result.exists():
            raise ValueError(f'Missing or escaping package path: {target}')
        return result

    thumbnail = target_path(info['Thumbnail'])
    if not thumbnail.is_file() or not thumbnail.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('Thumbnail must be a PNG file')
    if not info['InstallRule']:
        raise ValueError('At least one InstallRule is required')
    listings = read_json(package / 'listing.json')
    if listings != generate_listings(package):
        raise ValueError('Workshop listing text differs from localized READMEs')
    for language in LANGUAGES:
        target_path(f'README.{language}.md')
        if not all(isinstance(listings[language].get(key), str) and listings[language][key].strip()
                   for key in ('Title', 'Description')):
            raise ValueError(f'Missing Workshop listing text: {language}')
    for rule in info['InstallRule']:
        if rule['Type'] not in ('Lua', 'PalSchema', 'Paks'):
            raise ValueError('Unsupported InstallRule type')
        if 'IsServer' in rule and not isinstance(rule['IsServer'], bool):
            raise ValueError('InstallRule IsServer must be a boolean')
        if not isinstance(rule['Targets'], list) or not rule['Targets']:
            raise ValueError('InstallRule needs targets')
        for target in rule['Targets']:
            path = target_path(target)
            # The game copies directory contents only with a trailing slash.
            # Without it, PalSchema/ itself is nested under the mod root.
            if rule['Type'] == 'PalSchema' and (not target.endswith('/') or not path.is_dir() or
                    not any((path / name).is_dir() for name in ('raw', 'buildings', 'blueprints'))):
                raise ValueError('PalSchema target must end with / and directly contain raw/, buildings/ or blueprints/')
            if rule['Type'] == 'Paks' and (not target.endswith('/') or not path.is_dir() or
                    not any(p.is_file() for p in path.rglob('*.pak'))):
                raise ValueError('Paks target must end with / and contain a .pak file')
    return info


def prepare(mod, author=None, min_revision=None, version=None):
    template = MODS_ROOT / mod / 'workshop'
    generate_listings(template)
    info = read_json(template / 'Info.json')
    for key, value in [('Author', author), ('MinRevision', min_revision), ('Version', version)]:
        if value is not None:
            info[key] = value
    files = payload(mod)
    files += [(template / 'thumbnail.png', 'thumbnail.png')]
    files += [(template / f'README.{language}.md', f'README.{language}.md')
              for language in LANGUAGES]
    if mod == 'PalCombo':
        files += [(MODS_ROOT / mod / 'docs/LICENSE', 'LICENSE')]
    for src, dest in files:
        if src is not None and not src.is_file():
            raise FileNotFoundError(src)
    return info, files


def package_mod(mod, plan, output):
    info, files = plan
    destination = output / mod
    archive = output / (mod + '.zip')
    if destination.exists() or archive.exists():
        raise FileExistsError(f'Output already exists for {mod}; use a fresh --output-root')
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.workshop-', dir=output) as temporary:
        stage = Path(temporary) / mod
        stage.mkdir()
        for src, relative in files:
            target = stage / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if src is None:
                target.write_bytes(b'')
            else:
                shutil.copy2(src, target)
        (stage / 'Info.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        for language in LANGUAGES:
            rendered = render_readme(stage, language)
            (stage / f'README.{language}.md').write_text(rendered, encoding='utf-8')
        write_listings(stage, generate_listings(stage))
        validate(stage)
        manifest = {
            'PackageName': mod, 'Version': info['Version'],
            'Languages': list(LANGUAGES),
            'GameTest': 'Not verified by this packaging step',
            'Files': {p.relative_to(stage).as_posix(): digest(p) for p in sorted(stage.rglob('*')) if p.is_file()},
        }
        (stage / 'package-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
        zip_path = Path(temporary) / archive.name
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as bundle:
            for path in sorted(stage.rglob('*')):
                if path.is_file():
                    bundle.write(path, path.relative_to(stage).as_posix())
        stage.rename(destination)
        zip_path.rename(archive)
    return destination


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mods', nargs='*', metavar='MOD', help='Mod names or all (default: all)')
    parser.add_argument('--author', help='Override template author for all selected mods')
    parser.add_argument('--min-revision', type=int, help='Minimum game title revision; confirm before publishing')
    parser.add_argument('--version', help='Override package version for all selected mods')
    parser.add_argument('--listings-only', action='store_true', help='Generate listing.json files without builds or packages')
    parser.add_argument('--output-root', type=Path, help='Output directory (default: dist/workshop or dist/workshop-listings)')
    args = parser.parse_args(argv)
    for mod in args.mods:
        if mod not in (*MODS, 'all'):
            parser.error(f'Unknown mod: {mod}')
    selected = MODS if not args.mods or 'all' in args.mods else tuple(dict.fromkeys(args.mods))
    output = args.output_root or DIST_ROOT / ('workshop-listings' if args.listings_only else 'workshop')
    try:
        # Preflight all source inputs and destinations before creating any package.
        if args.listings_only:
            plans = {mod: generate_listings(MODS_ROOT / mod / 'workshop') for mod in selected}
        else:
            plans = {mod: prepare(mod, args.author, args.min_revision, args.version) for mod in selected}
        for mod in selected:
            if (output / mod).exists() or (output / (mod + '.zip')).exists():
                raise FileExistsError(f'Output already exists for {mod}; use a fresh --output-root')
        for mod in selected:
            if args.listings_only:
                folder = output / mod
                folder.mkdir(parents=True, exist_ok=True)
                write_listings(folder, plans[mod])
                print(f'Generated: {folder / "listing.json"}')
            else:
                print(f'Packaged: {package_mod(mod, plans[mod], output)}')
    except (OSError, ValueError, KeyError) as error:
        print(f'Workshop packaging failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
