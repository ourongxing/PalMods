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

MODS = ('BetterWorkbench', 'PalCombo', 'UpdraftElevator', 'PointBlankBurstSkills')
LANGUAGES = ('zh-Hans', 'zh-Hant', 'ja', 'en')


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def payload(mod):
    """Explicit runtime inputs exclude local jobs, logs, SDKs and old mod names."""
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
    elif mod == 'UpdraftElevator':
        schema = BUILD_ROOT / mod / 'stage/Mods/PalSchema/mods/UpdraftElevator'
        files += [(schema / 'buildings/wind_small.json', 'PalSchema/buildings/wind_small.json'),
                  (schema / 'paks/UpdraftElevator_P.pak', 'PalSchema/paks/UpdraftElevator_P.pak')]
        files += [(p, 'PalSchema/translations/' + p.relative_to(source / 'translations').as_posix())
                  for p in sorted((source / 'translations').rglob('*.json'))]
        # Use the generated helper so the Lua defaults match the packaged variants.
        helper = BUILD_ROOT / mod / 'stage/Mods/UpdraftElevator'
        files = [(helper / dest if dest.startswith('Scripts/') else src, dest) for src, dest in files]
    else:
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
    for language in LANGUAGES:
        target_path(f'README.{language}.md')
        if not all(isinstance(listings[language].get(key), str) and listings[language][key].strip()
                   for key in ('Title', 'Description')):
            raise ValueError(f'Missing Workshop listing text: {language}')
    for rule in info['InstallRule']:
        if rule['Type'] not in ('Lua', 'PalSchema') or rule.get('IsServer', False):
            raise ValueError('These packages support client installation rules only')
        if not isinstance(rule['Targets'], list) or not rule['Targets']:
            raise ValueError('InstallRule needs targets')
        for target in rule['Targets']:
            path = target_path(target)
            if rule['Type'] == 'PalSchema' and (not path.is_dir() or
                    not any((path / name).is_dir() for name in ('raw', 'buildings'))):
                raise ValueError('PalSchema target must directly contain raw/ or buildings/')
    return info


def prepare(mod, author=None, min_revision=None, version=None):
    template = MODS_ROOT / mod / 'workshop'
    info = read_json(template / 'Info.json')
    for key, value in [('Author', author), ('MinRevision', min_revision), ('Version', version)]:
        if value is not None:
            info[key] = value
    files = payload(mod)
    files += [(template / 'thumbnail.png', 'thumbnail.png'),
              (template / 'README.md', 'README.md'),
              (template / 'listing.json', 'listing.json')]
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
    parser.add_argument('--output-root', type=Path, default=DIST_ROOT / 'workshop')
    args = parser.parse_args(argv)
    for mod in args.mods:
        if mod not in (*MODS, 'all'):
            parser.error(f'Unknown mod: {mod}')
    selected = MODS if not args.mods or 'all' in args.mods else tuple(dict.fromkeys(args.mods))
    try:
        # Preflight all source inputs and destinations before creating any package.
        plans = {mod: prepare(mod, args.author, args.min_revision, args.version) for mod in selected}
        for mod in selected:
            if (args.output_root / mod).exists() or (args.output_root / (mod + '.zip')).exists():
                raise FileExistsError(f'Output already exists for {mod}; use a fresh --output-root')
        for mod in selected:
            print(f'Packaged: {package_mod(mod, plans[mod], args.output_root)}')
    except (OSError, ValueError, KeyError) as error:
        print(f'Workshop packaging failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
