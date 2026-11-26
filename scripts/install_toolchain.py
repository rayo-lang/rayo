"""Builds `rayo` and `rayoc` against the LLVM that `llvm-release.json` pins, and installs them with that LLVM's clang,
LLD and library as one toolchain, which then runs on a machine with no LLVM of its own.

    python3 scripts/install_toolchain.py                  # installs into $RAYO_HOME, or else ~/.rayo
    python3 scripts/install_toolchain.py --prefix <dir>   # installs into <dir>
"""

import argparse
import hashlib
import json
import os
import posixpath
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.error
import urllib.parse
import urllib.request

# The clone this script is in, which it builds.
REPOSITORY = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The LLD that `rayo` links each system's object files with.
SYSTEM_LLD = {'linux': 'ld.lld', 'macos': 'ld64.lld', 'windows': 'lld-link.exe'}

# A shared library's file name on Linux, versioned or not, or on macOS.
SHARED_LIBRARY = re.compile(r'\.so(\.|$)|\.dylib$')

# Python 3.12 and later can keep each unpacked file inside the folder it's unpacked into; on an older Python, the
# pinned checksum alone vouches for what an archive holds.
EXTRACTION_FILTER = {'filter': 'data'} if hasattr(tarfile, 'data_filter') else {}


class InstallError(Exception):
    """Why the install stopped, in words for the person who ran it."""


def main(arguments):
    parser = argparse.ArgumentParser(description='Installs the Rayo toolchain that this clone builds.')
    parser.add_argument('--prefix', help='the folder to install into, in place of $RAYO_HOME or ~/.rayo')
    options = parser.parse_args(arguments)
    try:
        home = os.path.abspath(toolchain_home(options.prefix, os.environ, os.path.expanduser('~')))
        version, system = install(home)
    # A file the install can't read or write stops it as plainly as a step that fails does.
    except (InstallError, OSError) as error:
        print(f'install_toolchain.py: {error}', file=sys.stderr)
        return 1

    print(f"Installed Rayo {version} in {os.path.join(home, 'toolchains', version)}. "
          'This puts it on the search path of the shell you are in:')
    bin_folder = os.path.join(home, 'bin')
    print(f'$env:Path = "{bin_folder};$env:Path"' if system == 'windows' else f'export PATH="{bin_folder}:$PATH"')
    return 0


def install(home):
    """Fetches the pinned LLVM, builds against it, and installs the toolchain into `home`. Returns the version it
    installed and the system it installed it for."""
    with open(os.path.join(REPOSITORY, 'llvm-release.json'), encoding='utf-8') as f:
        pin = json.load(f)
    with open(os.path.join(REPOSITORY, 'VERSION'), encoding='utf-8') as f:
        version = f.read().strip()

    triple = host_triple()
    system = host_of(triple).partition('-')[0]
    llvm = fetch_llvm(pinned_packages(pin, triple), os.path.join(REPOSITORY, '.build', 'llvm'))
    products = build_products(llvm, system)
    install_toolchain(llvm, products, home, version, system, clang_config(system))
    return version, system


def host_triple():
    """The target triple of the Swift compiler that builds the toolchain, which names the host it runs on."""
    info = json.loads(command_output(['swiftc', '-print-target-info']))
    return info['target']['triple']


def fetch_llvm(packages, folder):
    """Unpacks `packages` into one LLVM install inside `folder`, and returns its path. An install that an earlier
    run unpacked from the same packages is used again."""
    name = hashlib.sha256(json.dumps(packages, sort_keys=True).encode()).hexdigest()[:16]
    llvm = os.path.join(folder, name)
    if os.path.isdir(llvm):
        return llvm

    # Every package is downloaded and checked before any is unpacked, so a wrong one leaves nothing unpacked.
    downloads = os.path.join(folder, 'downloads')
    archives = []
    try:
        for package in packages:
            archives.append(download_checked(package, downloads))

        # The folder is unpacked apart, and named for its packages only once each of them is in it.
        staged = llvm + '.partial'
        shutil.rmtree(staged, ignore_errors=True)
        for package, archive in zip(packages, archives):
            unpack(archive, package.get('directory'), package['members'], staged)
        os.rename(staged, llvm)
    finally:
        for archive in archives:
            os.remove(archive)
    return llvm


def build_products(llvm, system):
    """Builds `rayo` and `rayoc` in release against the LLVM installed at `llvm`, and returns the folder that holds
    them."""
    # The build has a scratch path of its own, so it leaves the clone's own build, against its own LLVM, as it was.
    # SwiftPM caches what the manifest finds, which it mustn't take from a build against another LLVM.
    arguments = ['swift', 'build', '-c', 'release', '--scratch-path', os.path.join(REPOSITORY, '.build', 'install'),
                 '--manifest-cache', 'none']
    # The Swift runtime is part of macOS, and elsewhere part of the Swift install, which the toolchain mustn't need.
    if system != 'macos':
        arguments.append('--static-swift-stdlib')
    environment = {name: value for name, value in os.environ.items() if name != 'LLD_PREFIX'}
    environment['LLVM_PREFIX'] = llvm

    for product in ['rayo', 'rayoc']:
        run_command(arguments + ['--product', product], environment)
    return command_output(arguments + ['--show-bin-path'], environment).strip()


def clang_config(system):
    """What clang reads from the `clang.cfg` beside it: on macOS, the SDK a program links against, which LLVM's
    clang finds only when it's told; elsewhere, nothing."""
    if system != 'macos':
        return None
    return f"-isysroot {command_output(['xcrun', '--show-sdk-path']).strip()}\n"


def run_command(arguments, environment=None):
    """Runs a command from the clone, on the script's own output, and stops the install if it fails."""
    if subprocess.run(arguments, cwd=REPOSITORY, env=environment).returncode != 0:
        raise InstallError(f"'{' '.join(arguments)}' failed")


def command_output(arguments, environment=None):
    """Runs a command from the clone, and returns what it printed, or stops the install if it fails."""
    run = subprocess.run(arguments, cwd=REPOSITORY, env=environment, stdout=subprocess.PIPE, text=True)
    if run.returncode != 0:
        raise InstallError(f"'{' '.join(arguments)}' failed")
    return run.stdout


def host_of(triple):
    """The pin's name for the host a target triple names, such as `macos-aarch64` for `arm64-apple-macosx27.0`."""
    # A triple is the architecture, then the vendor and the system, such as `x86_64-unknown-linux-gnu`.
    architecture, _, rest = triple.partition('-')
    architecture = 'aarch64' if architecture == 'arm64' else architecture
    if '-linux' in triple:
        system = 'linux'
    elif '-apple-' in triple:
        system = 'macos'
    elif '-windows' in triple:
        system = 'windows'
    else:
        system = rest
    return f'{system}-{architecture}'


def pinned_packages(pin, triple):
    """The packages `pin` names for the host a target triple names, which hold the LLVM a toolchain carries there."""
    host = host_of(triple)
    hosts = pin['hosts']
    if host not in hosts:
        names = [f"'{name}'" for name in sorted(hosts)]
        listing = ', '.join(names[:-1]) + ' and ' + names[-1] if len(names) > 1 else names[0]
        raise InstallError(f"LLVM {pin['release']} is pinned for no '{host}' host, only for {listing}")
    return hosts[host]


def download_checked(package, downloads):
    """Downloads `package` into `downloads`, and returns the file's path once its SHA-256 is the pinned one."""
    archive, checksum = download(package['url'], downloads)
    if checksum != package['sha256']:
        os.remove(archive)
        raise InstallError(f"{package['url']} has SHA-256 {checksum}, not the pinned {package['sha256']}")
    return archive


def download(url, downloads):
    """Downloads `url` into `downloads`, and returns the file's path and its SHA-256, worked out as it arrives."""
    os.makedirs(downloads, exist_ok=True)
    path = os.path.join(downloads, posixpath.basename(urllib.parse.unquote(urllib.parse.urlparse(url).path)))
    print(f'Downloading {url}', flush=True)
    digest = hashlib.sha256()
    try:
        with urllib.request.urlopen(url, timeout=60) as response, open(path, 'wb') as file:
            while chunk := response.read(1 << 20):
                digest.update(chunk)
                file.write(chunk)
    except (urllib.error.URLError, OSError) as error:
        if os.path.exists(path):
            os.remove(path)
        raise InstallError(f"can't download {url}: {getattr(error, 'reason', error)}")
    return path, digest.hexdigest()


def unpack(archive, directory, members, prefix):
    """Unpacks the `members` of `archive` into `prefix`. Each member is a path inside the archive's `directory`, or
    inside the archive itself where it has none, and takes everything under it."""
    print(f'Unpacking {os.path.basename(archive)}', flush=True)
    root = directory + '/' if directory else ''
    # An archive is read once, as a stream, since an xz one would otherwise be decompressed again for each member.
    with tarfile.open(archive, 'r|*') as tar:
        for member in tar:
            name = member.name.removeprefix('./')
            path = name[len(root):] if name.startswith(root) else None
            if path is None or not any(path == wanted or path.startswith(wanted + '/') for wanted in members):
                continue

            # A hard link names its target by its path in the archive, which moves with the member.
            member.name = path
            if member.islnk():
                member.linkname = member.linkname.removeprefix('./').removeprefix(root)
            tar.extract(member, prefix, **EXTRACTION_FILTER)


def install_toolchain(llvm, products, home, version, system, clang_config):
    """Installs the toolchain of `version` into `home`, and makes it the one `home`'s `bin` runs. `system` is
    `linux`, `macos` or `windows`."""
    # The toolchain is laid out apart, and takes the place of one already installed only once it is whole.
    toolchains = os.path.join(home, 'toolchains')
    staged = os.path.join(toolchains, f'.{version}.partial')
    shutil.rmtree(staged, ignore_errors=True)
    lay_out_toolchain(llvm, products, staged, system, clang_config)
    replace_folder(os.path.join(toolchains, version), staged)

    make_default(home, version, system)


def replace_folder(folder, replacement):
    """Moves `replacement` to `folder`'s place, and removes the folder that was there."""
    # The old folder is moved aside before anything is removed, so one that Windows holds open, as it does a running
    # executable's, stops the install with the old folder whole.
    old = os.path.join(os.path.dirname(folder), f'.{os.path.basename(folder)}.old')
    shutil.rmtree(old, ignore_errors=True)
    if os.path.exists(old):
        raise InstallError(f"can't remove {old}, which an earlier install left, and which may be in use")
    moved_aside = os.path.exists(folder)
    if moved_aside:
        try:
            os.rename(folder, old)
        except OSError as error:
            raise InstallError(f"can't replace {folder}, which may be in use: {error}")

    # A replacement that can't move in puts the old folder back, so the version stays installed.
    try:
        os.rename(replacement, folder)
    except OSError:
        if moved_aside:
            os.rename(old, folder)
        raise
    shutil.rmtree(old, ignore_errors=True)


def lay_out_toolchain(llvm, products, toolchain, system, clang_config):
    """Lays out a toolchain in the new folder `toolchain`: `rayo` and `rayoc` from the build's `products`, with the
    clang, LLD and library of the LLVM installed at `llvm`, and a `clang.cfg` holding `clang_config` where it's
    given."""
    suffix = '.exe' if system == 'windows' else ''
    bin_folder = os.path.join(toolchain, 'bin')
    os.makedirs(bin_folder)

    # `rayo` runs the `rayoc`, clang and LLD beside it. Each is copied as the file a link to it names, since LLVM's
    # install links `clang` and the LLD of each object file format to other files.
    for name in ['rayo', 'rayoc']:
        shutil.copy2(os.path.join(products, name + suffix), bin_folder)
    for name in ['clang' + suffix, SYSTEM_LLD[system]]:
        shutil.copy2(os.path.join(llvm, 'bin', name), bin_folder)
    if clang_config is not None:
        with open(os.path.join(bin_folder, 'clang.cfg'), 'w', encoding='utf-8') as f:
            f.write(clang_config)

    # LLVM's library goes where `rayoc` looks for it first: beside `rayoc.exe` on Windows, and elsewhere in the
    # `lib` beside its `bin`, with the libraries it needs and the links that give it its other names.
    if system == 'windows':
        for name in sorted(os.listdir(os.path.join(llvm, 'bin'))):
            if name.endswith('.dll'):
                shutil.copy2(os.path.join(llvm, 'bin', name), bin_folder)
    else:
        lib_folder = os.path.join(toolchain, 'lib')
        os.makedirs(lib_folder)
        for name in sorted(os.listdir(os.path.join(llvm, 'lib'))):
            if SHARED_LIBRARY.search(name):
                shutil.copy2(os.path.join(llvm, 'lib', name), lib_folder, follow_symlinks=False)


def make_default(home, version, system):
    """Has `home`'s `bin` run the `rayo` and `rayoc` of the toolchain of `version`: through a symbolic link on Linux
    and macOS, and a batch file on Windows, which runs it with the same arguments and ends with its exit code."""
    bin_folder = os.path.join(home, 'bin')
    os.makedirs(bin_folder, exist_ok=True)
    for name in ['rayo', 'rayoc']:
        # Each names the toolchain's file from where it is, so the home can move with its toolchains.
        if system == 'windows':
            with open(os.path.join(bin_folder, name + '.cmd'), 'w', encoding='utf-8') as f:
                f.write(f'@"%~dp0..\\toolchains\\{version}\\bin\\{name}.exe" %*\n@exit /b %ERRORLEVEL%\n')
        else:
            link = os.path.join(bin_folder, name)
            if os.path.lexists(link):
                os.remove(link)
            os.symlink(os.path.join('..', 'toolchains', version, 'bin', name), link)


def toolchain_home(prefix, environment, user_home):
    """The folder a toolchain installs into: `prefix` when it's given, then `RAYO_HOME`, then `.rayo` in the user's
    home."""
    return prefix or environment.get('RAYO_HOME') or os.path.join(user_home, '.rayo')


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
