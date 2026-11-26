import contextlib
import hashlib
import io
import os
import pathlib
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import urllib.parse
import urllib.request

from install_toolchain import (
    InstallError, fetch_llvm, install_toolchain, make_default, pinned_packages, replace_folder, toolchain_home,
)

# A pin with a package for each of three hosts.
PIN = {'release': '1.2.3', 'hosts': {
    'linux-x86_64': [{'url': 'https://example.com/linux.tar.xz', 'sha256': 'a' * 64}],
    'macos-aarch64': [{'url': 'https://example.com/macos.tar.xz', 'sha256': 'b' * 64}],
    'windows-aarch64': [{'url': 'https://example.com/windows.tar.xz', 'sha256': 'c' * 64}],
}}


class PinnedPackagesTests(unittest.TestCase):
    def test_a_host_gets_the_packages_pinned_for_its_system_and_architecture(self):
        hosts = {
            'x86_64-unknown-linux-gnu': 'linux-x86_64',
            'arm64-apple-macosx27.0': 'macos-aarch64',
            'aarch64-unknown-windows-msvc': 'windows-aarch64',
        }
        for triple, host in hosts.items():
            with self.subTest(triple=triple):
                self.assertEqual(pinned_packages(PIN, triple), PIN['hosts'][host])

    def test_a_host_with_no_pinned_packages_is_refused_with_the_hosts_that_have_them(self):
        with self.assertRaises(InstallError) as raised:
            pinned_packages(PIN, 'aarch64-unknown-linux-gnu')
        self.assertEqual(
            str(raised.exception),
            "LLVM 1.2.3 is pinned for no 'linux-aarch64' host, only for 'linux-x86_64', 'macos-aarch64' and "
            "'windows-aarch64'",
        )


class ToolchainHomeTests(unittest.TestCase):
    def test_the_home_is_rayo_in_the_users_home_when_nothing_names_another(self):
        self.assertEqual(toolchain_home(None, {}, os.path.join('users', 'ada')), os.path.join('users', 'ada', '.rayo'))

    def test_rayo_home_moves_the_home(self):
        environment = {'RAYO_HOME': os.path.join('opt', 'rayo')}
        self.assertEqual(toolchain_home(None, environment, os.path.join('users', 'ada')), os.path.join('opt', 'rayo'))

    def test_the_prefix_moves_the_home_ahead_of_rayo_home(self):
        environment = {'RAYO_HOME': os.path.join('opt', 'rayo')}
        home = toolchain_home(os.path.join('tmp', 'toolchain'), environment, os.path.join('users', 'ada'))
        self.assertEqual(home, os.path.join('tmp', 'toolchain'))


class FetchLLVMTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = directory.name
        self.folder = os.path.join(self.directory, 'llvm')

        # LLVM's tools from an archive whose install is in a folder of its own, as LLVM's release archives hold theirs,
        # and its library from one whose install is the archive itself, as Julia's hold theirs.
        self.tools = self.archive('tools.tar.xz', 'w:xz', [
            ('llvm/bin/clang-23', b'clang'), ('llvm/bin/opt', b'opt'), ('llvm/include/llvm-c/Core.h', b'core'),
        ])
        self.library = self.archive('library.tar.gz', 'w:gz', [
            ('lib/libLLVM.so', b'llvm'), ('lib/libLLVMCore.a', b'core'),
        ])

    def archive(self, name, mode, files):
        """An archive of `files`, as a package that names it by its URL and SHA-256, with no members yet."""
        path = os.path.join(self.directory, name)
        with tarfile.open(path, mode) as archive:
            for member, content in files:
                add_file(archive, member, content)
        with open(path, 'rb') as f:
            checksum = hashlib.sha256(f.read()).hexdigest()
        return {'url': pathlib.Path(path).as_uri(), 'sha256': checksum}

    def packages(self, tools_members=('bin/clang-23', 'include/llvm-c'), library_checksum=None):
        return [
            dict(self.tools, directory='llvm', members=list(tools_members)),
            dict(self.library, members=['lib/libLLVM.so'], sha256=library_checksum or self.library['sha256']),
        ]

    def fetch(self, packages):
        with contextlib.redirect_stdout(io.StringIO()):
            return fetch_llvm(packages, self.folder)

    def test_the_packages_unpack_the_members_they_name_into_one_folder(self):
        llvm = self.fetch(self.packages())

        self.assertEqual(sorted(files_under(llvm)), ['bin/clang-23', 'include/llvm-c/Core.h', 'lib/libLLVM.so'])
        self.assertEqual(os.listdir(os.path.join(self.folder, 'downloads')), [])

    def test_a_checksum_that_differs_stops_the_fetch_before_any_package_is_unpacked(self):
        with self.assertRaises(InstallError) as raised:
            self.fetch(self.packages(library_checksum='0' * 64))

        self.assertEqual(str(raised.exception),
                         f"{self.library['url']} has SHA-256 {self.library['sha256']}, not the pinned {'0' * 64}")
        self.assertEqual(list(files_under(self.folder)), [])

    def test_a_folder_fetched_before_is_used_again_without_a_download(self):
        llvm = self.fetch(self.packages())
        for package in [self.tools, self.library]:
            os.remove(pathlib.Path(urllib.request.url2pathname(urllib.parse.urlparse(package['url']).path)))

        self.assertEqual(self.fetch(self.packages()), llvm)

    def test_packages_that_name_other_members_are_unpacked_again(self):
        self.fetch(self.packages())

        llvm = self.fetch(self.packages(tools_members=['bin/clang-23', 'bin/opt']))

        self.assertEqual(sorted(files_under(llvm)), ['bin/clang-23', 'bin/opt', 'lib/libLLVM.so'])

    @unittest.skipIf(os.name == 'nt', 'Windows makes symbolic links only for an administrator')
    def test_links_are_unpacked_as_links_to_where_their_targets_are_unpacked(self):
        path = os.path.join(self.directory, 'links.tar.xz')
        with tarfile.open(path, 'w:xz') as archive:
            add_file(archive, 'llvm/bin/clang-23', b'clang')
            add_link(archive, 'llvm/bin/clang', 'clang-23')
            add_file(archive, 'llvm/bin/lld', b'lld')
            add_hard_link(archive, 'llvm/bin/ld.lld', 'llvm/bin/lld')
        with open(path, 'rb') as f:
            checksum = hashlib.sha256(f.read()).hexdigest()
        package = {'url': pathlib.Path(path).as_uri(), 'sha256': checksum, 'directory': 'llvm', 'members': ['bin']}

        llvm = self.fetch([package])

        self.assertEqual(os.readlink(os.path.join(llvm, 'bin', 'clang')), 'clang-23')
        self.assertTrue(os.path.samefile(os.path.join(llvm, 'bin', 'ld.lld'), os.path.join(llvm, 'bin', 'lld')))


@unittest.skipIf(os.name == 'nt', "the LLVM installs stood in for hold symbolic links, which Windows makes only for "
                                  "an administrator")
class InstallToolchainTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = directory.name
        self.home = os.path.join(self.directory, 'home')

    def llvm(self, layout):
        """An LLVM install holding `layout`, which maps each path to its content, or to `('link', target)`."""
        llvm = os.path.join(self.directory, 'llvm')
        for path, content in layout.items():
            write(os.path.join(llvm, path), content)
        return llvm

    def products(self, rayo=b'rayo', executable_suffix=''):
        """A build's products folder, holding `rayo` and `rayoc` among what else a build makes."""
        products = os.path.join(self.directory, 'products')
        write(os.path.join(products, 'rayo' + executable_suffix), rayo)
        write(os.path.join(products, 'rayoc' + executable_suffix), b'rayoc')
        write(os.path.join(products, 'RayoDriver.swiftmodule', 'arm64.swiftmodule'), b'module')
        return products

    def toolchain(self, *path):
        return os.path.join(self.home, 'toolchains', '0.3.0', *path)

    def test_a_linux_toolchain_holds_rayo_rayoc_clang_ld_lld_and_llvms_library_with_its_names(self):
        llvm = self.llvm({
            'bin/clang': ('link', 'clang-23'), 'bin/clang-23': b'clang', 'bin/lld': b'lld',
            'bin/ld.lld': ('link', 'lld'), 'bin/llvm-config': b'config', 'include/llvm-c/Core.h': b'core',
            'lib/libLLVM.so.23.1jl': b'llvm', 'lib/libLLVM.so': ('link', 'libLLVM.so.23.1jl'),
            'lib/libLLVM-23jl.so': ('link', 'libLLVM.so.23.1jl'), 'lib/libLLVMCore.a': b'core',
            'lib/cmake/llvm/LLVMConfig.cmake': b'cmake',
        })

        install_toolchain(llvm, self.products(), self.home, '0.3.0', 'linux', clang_config=None)

        self.assertEqual(sorted(files_under(self.toolchain())), [
            'bin/clang', 'bin/ld.lld', 'bin/rayo', 'bin/rayoc',
            'lib/libLLVM-23jl.so', 'lib/libLLVM.so', 'lib/libLLVM.so.23.1jl',
        ])
        self.assertEqual(read(self.toolchain('bin', 'clang')), b'clang')
        self.assertEqual(read(self.toolchain('bin', 'ld.lld')), b'lld')
        self.assertEqual(os.readlink(self.toolchain('lib', 'libLLVM.so')), 'libLLVM.so.23.1jl')
        self.assertTrue(os.access(self.toolchain('bin', 'clang'), os.X_OK))

    def test_a_macos_toolchain_holds_ld64_lld_the_libraries_llvms_needs_and_clangs_options(self):
        llvm = self.llvm({
            'bin/clang': b'clang', 'bin/lld': b'lld', 'bin/ld64.lld': ('link', 'lld'),
            'lib/libLLVM.23.1jl.dylib': b'llvm', 'lib/libLLVM.dylib': ('link', 'libLLVM.23.1jl.dylib'),
            'lib/libzstd.1.dylib': b'zstd', 'lib/libLLVMCore.a': b'core',
        })

        install_toolchain(llvm, self.products(), self.home, '0.3.0', 'macos',
                          clang_config='-isysroot /SDKs/MacOSX.sdk\n')

        self.assertEqual(sorted(files_under(self.toolchain())), [
            'bin/clang', 'bin/clang.cfg', 'bin/ld64.lld', 'bin/rayo', 'bin/rayoc',
            'lib/libLLVM.23.1jl.dylib', 'lib/libLLVM.dylib', 'lib/libzstd.1.dylib',
        ])
        self.assertEqual(read(self.toolchain('bin', 'clang.cfg')), b'-isysroot /SDKs/MacOSX.sdk\n')

    def test_a_windows_toolchain_holds_lld_link_and_llvm_c_beside_rayo(self):
        llvm = self.llvm({
            'bin/clang.exe': b'clang', 'bin/lld.exe': b'lld', 'bin/lld-link.exe': b'lld-link', 'bin/LLVM-C.dll': b'c',
            'lib/LLVM-C.lib': b'import library', 'include/llvm-c/Core.h': b'core',
        })

        install_toolchain(llvm, self.products(executable_suffix='.exe'), self.home, '0.3.0', 'windows',
                          clang_config=None)

        self.assertEqual(sorted(files_under(self.toolchain())), [
            'bin/LLVM-C.dll', 'bin/clang.exe', 'bin/lld-link.exe', 'bin/rayo.exe', 'bin/rayoc.exe',
        ])

    def test_the_homes_bin_runs_the_toolchains_rayo_and_rayoc(self):
        llvm = self.llvm({'bin/clang': b'clang', 'bin/ld.lld': b'lld', 'lib/libLLVM.so': b'llvm'})

        install_toolchain(llvm, self.products(), self.home, '0.3.0', 'linux', clang_config=None)

        for name in ['rayo', 'rayoc']:
            with self.subTest(name=name):
                link = os.path.join(self.home, 'bin', name)
                self.assertEqual(os.readlink(link), os.path.join('..', 'toolchains', '0.3.0', 'bin', name))
                self.assertEqual(os.path.realpath(link), os.path.realpath(self.toolchain('bin', name)))

    def test_installing_a_version_again_replaces_its_folder(self):
        llvm = self.llvm({'bin/clang': b'clang', 'bin/ld.lld': b'lld', 'lib/libLLVM.so': b'llvm'})
        install_toolchain(llvm, self.products(rayo=b'first'), self.home, '0.3.0', 'linux', clang_config=None)
        write(self.toolchain('bin', 'left-over'), b'stale')

        install_toolchain(llvm, self.products(rayo=b'second'), self.home, '0.3.0', 'linux', clang_config=None)

        self.assertEqual(os.listdir(os.path.join(self.home, 'toolchains')), ['0.3.0'])
        self.assertEqual(read(self.toolchain('bin', 'rayo')), b'second')
        self.assertFalse(os.path.exists(self.toolchain('bin', 'left-over')))


class ReplaceFolderTests(unittest.TestCase):
    def test_a_replacement_that_cant_move_in_leaves_the_old_folder_where_it_was(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = os.path.join(directory, '0.3.0')
            write(os.path.join(folder, 'bin', 'rayo'), b'old')

            with self.assertRaises(OSError):
                replace_folder(folder, os.path.join(directory, 'missing'))

            self.assertEqual(read(os.path.join(folder, 'bin', 'rayo')), b'old')


@unittest.skipUnless(os.name == 'nt', 'the shims are batch files, which only Windows runs')
class WindowsShimTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.home = directory.name

        # The toolchain's `rayo.exe` is a copy of the command interpreter, which echoes and exits as it's told.
        bin_folder = os.path.join(self.home, 'toolchains', '0.3.0', 'bin')
        os.makedirs(bin_folder)
        shutil.copy2(os.path.join(os.environ['SystemRoot'], 'System32', 'cmd.exe'),
                     os.path.join(bin_folder, 'rayo.exe'))
        make_default(self.home, '0.3.0', 'windows')
        self.shim = os.path.join(self.home, 'bin', 'rayo.cmd')

    def test_a_shim_passes_its_arguments_on(self):
        run = subprocess.run([self.shim, '/c', 'echo', 'a', 'b c'], capture_output=True, text=True)
        self.assertEqual(run.stdout, 'a "b c"\n')

    def test_a_shim_ends_with_the_exit_code_of_what_it_runs(self):
        run = subprocess.run([self.shim, '/c', 'exit', '7'], capture_output=True, text=True)
        self.assertEqual(run.returncode, 7)


def write(path, content):
    """Writes `content` to `path`, or makes it a symbolic link where `content` is `('link', target)`."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(content, tuple):
        os.symlink(content[1], path)
        return
    with open(path, 'wb') as f:
        f.write(content)
    os.chmod(path, 0o755)


def read(path):
    with open(path, 'rb') as f:
        return f.read()


def add_file(archive, name, content):
    member = tarfile.TarInfo(name)
    member.size = len(content)
    member.mode = 0o755
    archive.addfile(member, io.BytesIO(content))


def add_link(archive, name, target):
    member = tarfile.TarInfo(name)
    member.type = tarfile.SYMTYPE
    member.linkname = target
    archive.addfile(member)


def add_hard_link(archive, name, target):
    """Adds a hard link, which names its target by the target's path in the archive."""
    member = tarfile.TarInfo(name)
    member.type = tarfile.LNKTYPE
    member.linkname = target
    archive.addfile(member)


def files_under(directory):
    """The paths of the files and links under `directory`, relative to it, with forward slashes."""
    for root, _, files in os.walk(directory):
        for name in files:
            yield os.path.relpath(os.path.join(root, name), directory).replace(os.sep, '/')


if __name__ == '__main__':
    unittest.main()
