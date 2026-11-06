#!/bin/sh
set -eu
repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
python3 - "$repo" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import quote_from_bytes

repo = Path(sys.argv[1])
shells = {name: shutil.which(name) for name in ('bash', 'zsh')}
for name, executable in shells.items():
    if executable is None:
        raise SystemExit(f'Required shell is missing: {name}')


def check(actual, expected, label):
    if actual != expected:
        # repr keeps terminal controls inert even on failures.
        raise AssertionError(f'{label}: expected {expected!r}, got {actual!r}')


with tempfile.TemporaryDirectory(prefix='dotfiles-shell-') as temporary:
    root = Path(temporary)
    home = root / 'home'
    cwd = root / 'unrelated'
    tools = root / 'tools'
    checkout = home / 'checkout' / 'shell'
    for directory in (home, cwd, tools, checkout):
        directory.mkdir(parents=True, exist_ok=True)
    for name in ('readlink', 'dirname'):
        executable = shutil.which(name)
        if executable is None:
            raise SystemExit(f'Required utility is missing: {name}')
        (tools / name).symlink_to(executable)
    (tools / 'dircolors').write_text('#!/bin/sh\nexit 0\n')
    (tools / 'dircolors').chmod(0o755)
    (checkout / 'common.sh').write_text('COMMON_MARKER=expected\n')
    (cwd / 'common.sh').write_text('COMMON_MARKER=planted\n')
    (cwd / 'checkout' / 'shell').mkdir(parents=True)
    (cwd / 'checkout' / 'shell' / 'common.sh').write_text('COMMON_MARKER=planted\n')

    # Relocate fixed macOS prefixes into the sandbox, without touching host paths.
    native = root / 'native' / 'bin'
    intel = root / 'intel' / 'bin'
    for directory in (native, intel):
        directory.mkdir(parents=True)
    prefix = root / 'brew-prefix'
    java = prefix / 'opt' / 'openjdk' / 'bin'
    include = prefix / 'opt' / 'openjdk' / 'include'
    java.mkdir(parents=True)
    include.mkdir()
    for directory in (native, intel):
        (directory / 'brew').write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_BREW_PREFIX"\n')
        (directory / 'brew').chmod(0o755)
    for name in shells:
        text = (repo / 'shell' / f'{name}rc').read_text()
        text = text.replace('/opt/homebrew/bin', str(native))
        text = text.replace('/usr/local/bin', str(intel))
        text = text.replace('/usr/local/go/bin', str(root / 'absent-go'))
        (checkout / f'{name}rc').write_text(text)

    result = root / 'result'

    def run(name, code, path=None, extra=None):
        result.unlink(missing_ok=True)
        env = {
            'HOME': str(home), 'ZDOTDIR': str(home), 'PATH': path or str(tools),
            'TERM': 'dumb', 'LC_ALL': 'C', 'USER': 'tester', 'HOST': 'example',
            'RESULT': str(result), 'TEST_BREW_PREFIX': str(prefix),
        }
        if extra:
            env.update(extra)
        if name == 'bash':
            args = ['--noprofile', '--norc', '-ic', 'set -o posix; ' + code]
        else:
            args = ['-f', '-i', '-c', code]
        completed = subprocess.run([shells[name], *args], cwd=cwd, env=env,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if completed.returncode:
            raise AssertionError(f'{name} failed: {completed.stdout!r} {completed.stderr!r}')
        return result.read_bytes()

    for name in shells:
        link = home / f'.{name}rc'
        for relative in (False, True):
            link.unlink(missing_ok=True)
            target = f'checkout/shell/{name}rc' if relative else str(checkout / f'{name}rc')
            link.symlink_to(target)
            actual = run(name, f'. "$HOME/.{name}rc"; printf "%s" "$COMMON_MARKER" > "$RESULT"')
            check(actual, b'expected', f'{name} relative={relative} from unrelated cwd')
        # A bare relative target must resolve against HOME too, not the current directory.
        link.unlink()
        (home / f'{name}rc').symlink_to(checkout / f'{name}rc')
        (home / 'common.sh').write_text('COMMON_MARKER=expected\n')
        link.symlink_to(f'{name}rc')
        check(run(name, f'. "$HOME/.{name}rc"; printf "%s" "$COMMON_MARKER" > "$RESULT"'),
              b'expected', f'{name} bare relative target')
        link.unlink()
        link.symlink_to(checkout / f'{name}rc')

    # Both intentional architecture orders survive repeated sourcing and deduplication.
    for first, second in ((native, intel), (intel, native)):
        initial = f'{first}:{second}:{tools}:{first}'
        for repetitions in (1, 2):
            code = 'OSTYPE=darwin; ' + '. "$HOME/.zshrc"; ' * repetitions
            actual = run('zsh', code + 'printf "%s\\n%s" "$PATH" "$CPPFLAGS" > "$RESULT"', initial)
            expected = f'{java}:{first}:{second}:{tools}\n-I{include}'.encode()
            check(actual, expected, f'brew order {first.name}/{first.parent.name}, repeat {repetitions}')
    for initial, ordered in ((str(tools), [tools, native, intel]),
                             (f'{intel}:{tools}', [intel, tools, native]),
                             (f'{native}:{tools}', [native, tools, intel])):
        actual = run('zsh', 'OSTYPE=darwin; . "$HOME/.zshrc"; . "$HOME/.zshrc"; '
                     'printf "%s" "$PATH" > "$RESULT"', initial)
        check(actual, ':'.join(map(str, [java, *ordered])).encode(), 'append missing brew prefixes')
    # An absent prefix must not be inserted.
    (native / 'brew').unlink()
    native.rmdir()
    actual = run('zsh', 'OSTYPE=darwin; . "$HOME/.zshrc"; printf "%s" "$PATH" > "$RESULT"')
    check(actual, f'{java}:{tools}:{intel}'.encode(), 'ignore absent brew prefix')

    cases = [b'/ordinary/a-Z_0.~', b'/space here', '/한글/é'.encode(),
             b'/percent%20', b'/punctuation!"#$&\'()*+,:;=?@[\\]^`{|}',
             b'/controls\x01\x07\x1b\n\r\t\x7f', b'/high\xff\x80']
    for index, directory in enumerate(cases):
        for tmux in (False, True):
            # Environment values preserve bytes; no control-bearing text is emitted live.
            extra = {'TEST_DIRECTORY': os.fsdecode(directory),
                     'TEST_USER': 'tester' if index == 0 else 'u\x07\x1b%/@',
                     'TEST_HOST': 'example' if index == 0 else 'h\n\x1b%/é',
                     'TMUX': 'sandbox' if tmux else ''}
            actual = run('zsh', '. "$HOME/.zshrc"; PWD="$TEST_DIRECTORY"; '
                         'USER="$TEST_USER"; HOST="$TEST_HOST"; '
                         '_ghostty_osc7_cwd > "$RESULT"', extra=extra)
            user = quote_from_bytes(extra['TEST_USER'].encode(), safe='-._~')
            host = quote_from_bytes(extra['TEST_HOST'].encode(), safe='-._~')
            path = quote_from_bytes(directory, safe='/-._~')
            expected = b'\x1b]7;file://' + f'{user}@{host}{path}'.encode() + b'\x07'
            if tmux:
                expected = b'\x1bPtmux;' + expected.replace(b'\x1b', b'\x1b\x1b') + b'\x1b\\'
            check(actual, expected, f'OSC7 case {index}, tmux={tmux}')

print('Shell boundary regressions passed')
PY
