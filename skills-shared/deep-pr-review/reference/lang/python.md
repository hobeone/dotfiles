# Python profile

Claims marked "verified" were run on CPython 3.13; unmarked ones are standard
documented behaviour. Check the project's minimum supported version
(`requires-python`, `python_requires`, CI matrix) before applying a
version-gated bullet.

## Detection

- Extensions `.py`, `.pyi`, `.pyw`; shebangs `#!/usr/bin/env python`, `python3`.
- Project signals: `pyproject.toml`, `setup.py`, `requirements*.txt`, `tox.ini`, `conftest.py`.
- Python embedded in other files (CI `run:` blocks with `python -c`, notebooks `.ipynb` code cells): apply the profile to those lines.

## Do not flag

- **A default argument that is immutable or never mutated:** `def f(x=None)`, `def f(opts=())`, `def f(mode="r")`, `def f(names=frozenset())`. Why: the shared-default bug needs a mutable object that the function mutates; tuples, frozensets, strings, numbers and `None` cannot carry state between calls. A mutable default that the function only reads is also safe, though worth a note.
- **A mutable default used on purpose as a cache or memo** (`def fib(n, _memo={})`) when the name or a comment says so. Why: the default is evaluated once at definition time, which is exactly the persistence the author wants; flag it only if the state is also a hidden shared-between-callers or thread-safety hazard.
- **A lambda or inner function in a loop that is called inside the same iteration** (`for i in xs: g = lambda: i; use(g())`). Why: late binding only bites when the closure outlives the iteration; calling it immediately sees the current `i` (verified: results `[0, 1, 2]`). The bug is a closure stored or returned and called later (verified: `[lambda: i for i in range(3)]` returns `[2, 2, 2]`).
- **Names in annotations that are not imported at runtime**, quoted forward references (`"Node"`), and `if TYPE_CHECKING:` imports used only in annotations. Why: with string annotations or `from __future__ import annotations` they are never evaluated at definition time, and Python 3.14 evaluates annotations lazily by default (PEP 649; not run here, which is 3.13). It is a bug only if the name is also used at runtime, e.g. in `isinstance`, `cast` with a non-string argument, or `get_type_hints` on a pydantic or dataclass field that needs it.
- **`x is None`, `x is not None`, `x is True`, and `is` against a module-level sentinel** (`_MISSING = object()`). Why: identity is the correct test for singletons and sentinels; `== None` is the style problem. `is` against an int or str literal is a real bug (verified: CPython warns `"is" with 'int' literal`).
- **Re-export imports in `__init__.py` and `# noqa: F401` imports** whose only purpose is a side effect (registering a plugin, a codec, an ORM model). Why: they look unused to a linter but define the public surface or trigger registration; check `__all__` or the import-for-effect comment before flagging.
- **`assert` in test files** (pytest, unittest-style asserts). Why: tests are not run with `python -O`, and pytest rewrites assertions to report operands. The same `assert` used to validate input in library code is a bug (see Common bugs).
- **`subprocess.run([...])` with a list argument and `shell=False`, or `shell=True` with a literal command string containing no interpolation.** Why: there is no shell parsing of data; injection needs untrusted text reaching a shell command line.
- **`except Exception:` at the top of a worker loop, CLI `main`, or request handler that logs with the traceback and continues or exits non-zero.** Why: it is the process boundary; swallowing is the bug only when the handler drops the error silently. A bare `except:` or `except BaseException:` is still worth a look, since it catches `KeyboardInterrupt` and `SystemExit`.

## Common bugs

- **Mutable default argument that is mutated** (`def f(x, acc=[]): acc.append(x)`): the list is shared by every call (verified: the first call returns `[1]`, the second `[1, 1]`). Use `None` and create inside.
- **Late-binding closures stored for later** (lambdas in a list comprehension, callbacks registered in a loop): bind with a default argument (`lambda i=i: i`, verified `[0, 1, 2]`).
- **Changing a collection while iterating it:** adding a key to a dict raises `RuntimeError: dictionary changed size during iteration`; removing from a list while looping skips elements (verified: `[1, 2, 3, 4]` filtered in place leaves `[1, 3]`). Iterate over a copy or build a new collection.
- **Truthiness used for presence:** `if not value` / `value or default` treat `0`, `0.0`, `""`, `[]` as missing. Use `is None` when zero or empty is a valid value.
- **`str.strip`, `lstrip`, `rstrip` given a prefix or suffix:** the argument is a set of characters, not a string (verified: `"ab_foo".lstrip("ab_")` gives `foo` but `"abba".lstrip("ab")` gives an empty string). Use `removeprefix`/`removesuffix` (3.9+) or slicing.
- **Naive and aware datetimes mixed:** comparing them raises `TypeError` (verified); `datetime.utcnow()` and `datetime.now()` return naive values and are easy to mix with aware ones. Prefer `datetime.now(timezone.utc)`.
- **`zip()` silently truncating to the shorter input** (verified); use `zip(..., strict=True)` (3.10+) when lengths must match.
- **A generator, `map`, `filter` or file object consumed twice:** the second pass sees nothing.
- **`assert` used for validation or security checks:** removed under `python -O` (verified: the assertion did not run). Raise an exception.
- **Forgotten `await` / blocking inside `async def`:** calling a coroutine function without `await` creates a coroutine that never runs (verified: `RuntimeWarning: coroutine 'f' was never awaited`); `time.sleep`, `requests.get` or blocking file/DB calls inside an event loop stall every task. `asyncio.create_task(...)` whose result is not stored can be garbage-collected mid-run (the asyncio documentation says to keep a reference).
- **No timeout on network calls:** `requests.get(url)` waits indefinitely by default; `urllib.request.urlopen` uses the global default (none). Pass `timeout=`.
- **Text I/O with the locale's default encoding:** `open(path)` or `read_text()` without `encoding=` decodes with the platform locale unless UTF-8 mode is on, so the same file fails on another machine. State `encoding="utf-8"` for files meant to be UTF-8.
- **`tempfile.mktemp`** (name returned before creation, so racy): use `mkstemp`, `NamedTemporaryFile` or `TemporaryDirectory`.
- **Catching too broadly or too early:** `except Exception: pass`, an `except` that logs and falls through into code that uses the unset result, `raise NewError(...)` inside `except` without `from e`, losing the cause.
- **Resource handling:** files, sockets, locks and DB connections opened without `with` or a `finally` on the failure path.

## Trust boundaries

- Anything from a network request (query string, headers, body, cookies, uploaded filename and content), CLI arguments, environment variables, and file contents read from user-writable locations.
- Deserialisers that execute code or build arbitrary objects: `pickle`, `marshal`, `shelve`, `yaml.load` with `Loader=yaml.Loader` or `UnsafeLoader` (verified: `!!python/object/apply:os.getcwd []` executed a call; `FullLoader` rejected it, but `yaml.safe_load` is the call meant for untrusted input), and `jsonpickle`. PyYAML 6 requires `yaml.load` to be given a `Loader` argument (verified).
- Dynamic code and names: `eval`, `exec`, `compile`, `__import__`/`importlib.import_module(name)`, `getattr(obj, name)` with a user-supplied `name`.
- Shell and SQL: `os.system`, `subprocess` with `shell=True` and an interpolated string, and `cursor.execute(f"... {x}")` or `%`-formatted SQL (use bound parameters).
- Filesystem paths: `os.path.join(base, user)` discards `base` when `user` is absolute (verified: gives `/etc/passwd`) and keeps `..` segments (verified); `open(user_path)` and `send_file(user_path)` need `Path.resolve()` plus a containment check. Archive extraction (`zipfile.extractall`, `tarfile.extractall`) can write outside the target through `..` or absolute member names; for tarfile pass `filter="data"` (per PEP 706 the default filter only becomes `data` in 3.14, so on older versions an unfiltered `extractall` trusts the archive).
- Format and template strings: `str.format` on an attacker-controlled format string can read attributes and globals (verified: `"{0.__init__.__globals__[G]}".format(obj)` returned a module global); `jinja2.Template(user_text)` outside a sandbox executes arbitrary expressions.
- XML from outside: the standard `xml.*` parsers are documented as unsafe against maliciously constructed data (entity expansion); use `defusedxml`.
- Regexes built from or applied to untrusted text can backtrack catastrophically; randomness for tokens must come from `secrets`, not `random`.
