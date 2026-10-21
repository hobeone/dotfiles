# TypeScript / JavaScript profile (including Svelte script blocks)

Claims marked "verified" were run on Node 24; Svelte and TypeScript-compiler
claims are documented behaviour and were not run (neither is installed here).
Check `tsconfig.json` (`strict`, `useUnknownInCatchVariables`), the Node
version and the Svelte major version before applying a version-gated bullet.

## Detection

- Extensions `.ts`, `.tsx`, `.mts`, `.cts`, `.js`, `.jsx`, `.mjs`, `.cjs`; shebang `#!/usr/bin/env node`.
- `.svelte` files and `.svelte.ts` / `.svelte.js` modules: review the `<script>` blocks as TypeScript/JavaScript, and the markup for the sinks listed under Trust boundaries.
- Project signals: `package.json`, `tsconfig.json`, `svelte.config.js`, `vite.config.*`.
- Skip generated or built output (`dist/`, `build/`, `.svelte-kit/`, `*.d.ts` emitted from sources, `node_modules/`): a defect there belongs to the source or the generator.

## Do not flag

- **`x == null` and `x != null`.** Why: loose equality against `null` is true for both `null` and `undefined` and nothing else (verified: `null == undefined` is true, `0 == null` and `"" == null` are false), so it is the compact way to test "absent". Any other `==` is still worth a look (verified: `0 == ""` and `"0" == false` are true).
- **`void somePromise()` and `void` on an intentionally detached call.** Why: it is the explicit marker that the result is deliberately not awaited (typescript-eslint's `no-floating-promises` accepts it by default). The call still needs its own error handling; see Common bugs.
- **An `async` function with no `await`.** Why: it still returns a Promise and turns a thrown error into a rejection, which is often the contract (an interface or callback that must return a Promise).
- **Awaiting inside a `for...of` loop** (`for (const x of xs) await f(x)`). Why: it is the correct way to keep order, apply backpressure, or stop at the first failure; `Promise.all(xs.map(f))` changes all three. Flag it only when the iterations are independent and the code gives no reason to serialise.
- **`path.join(base, userPath)` treated as if an absolute `userPath` replaces `base`.** Why: `path.join` concatenates (verified: `join('/srv/uploads', '/etc/passwd')` is `/srv/uploads/etc/passwd`), unlike Python's `os.path.join` and unlike `path.resolve`, which does replace it (verified: `/etc/passwd`). The `..` segments in `userPath` still escape `base` (verified), so the traversal finding is real and the absolute-path variant is not.
- **`@ts-expect-error` (as opposed to `@ts-ignore`) in tests, with a stated reason.** Why: the compiler errors if the suppressed error disappears, so the assertion cannot rot silently.
- **`import "./side-effect"` and `import type { T }` lines with no usage in the value space.** Why: the first runs for its effect (polyfills, CSS, registration); the second is erased at compile time and is meant to have no runtime use.
- **Svelte rune calls (`$state`, `$derived`, `$effect`, `$props`, `$bindable`, `$inspect`) and `$store` auto-subscriptions in `.svelte` files without an import or declaration.** Why: runes are keywords the compiler understands, and `$name` in a component is the compiler's store subscription for a store named `name`; neither is an undefined identifier. In Svelte 4 code, `$:` is a reactive statement, not an unused label.
- **In-place mutation of a Svelte 5 `$state` object or array** (`todos.push(t)`, `user.name = "x"`). Why: `$state` wraps plain objects and arrays in a deeply reactive proxy, so mutation notifies dependents. It does not apply to class instances, `Map`, `Set` or `Date` (use `SvelteMap`, `SvelteSet`, `SvelteDate` from `svelte/reactivity`, or reassign), and in Svelte 4 `push` without reassignment really does not update.

## Common bugs

- **Callbacks that look synchronous but are not awaited:** `arr.forEach(async (x) => { await ... })` returns before the work finishes (verified: length 0 right after the call); use `for...of` or `Promise.all(arr.map(...))`.
- **Floating promises:** an un-awaited call with no `.catch` rejects into an unhandled rejection, which terminates a Node process by default (verified: exit code 1). Pair every detached promise with a catch.
- **`fetch` resolves on HTTP errors:** a 404 or 500 does not reject (verified: resolved with `ok === false`, status 404). Check `res.ok` before `res.json()`.
- **Types are erased at runtime:** `JSON.parse(text) as Config`, `(await res.json()) as User` and a type annotation on `process.env.X` check nothing. Validate with a runtime schema or narrow explicitly before use.
- **`Array.prototype.sort()` with no comparator sorts by string** (verified: `[10, 9, 1, 100].sort()` is `[1, 10, 100, 9]`); `.map(parseInt)` passes the index as the radix (verified: `[1, NaN, NaN]`); `parseInt` without a radix on untrusted strings; `isNaN("abc")` is true while `Number.isNaN("abc")` is false (verified).
- **Falsy-zero and empty-string checks:** `count || 5`, `if (!value)` replace a legitimate `0` or `""` (verified: `0 || 5` is `5`, `0 ?? 5` is `0`). Use `??` or an explicit `=== undefined`.
- **`typeof x === "object"` is true for `null`** (verified); check `x !== null` too.
- **Shared references from `Array(n).fill([])` or `fill({})`:** every slot is the same object (verified).
- **`var` in loops captured by closures:** all closures see the final value (verified: `[3, 3, 3]`; `let` gives `[0, 1, 2]`).
- **Dates:** a date-only ISO string (`new Date("2024-01-01")`) is parsed as UTC while a date-time string without an offset is parsed as local time (verified under `TZ=America/New_York`: the two differ by the 5-hour offset).
- **`JSON.parse(JSON.stringify(x))` as a deep clone** drops `undefined`, functions and symbols and turns `Date` into a string (verified); `structuredClone` keeps dates.
- **`for...in` over an array** yields string indices and inherited enumerable keys; **shallow copies** (`{...a}`, `Object.assign`) share nested objects.
- **`Promise.all` rejecting on the first failure** while the other promises keep running and their errors go unobserved; use `allSettled` when each result matters.
- **`catch (e)` with `e.message` on an `unknown`/`any` value** that may not be an `Error` (anything can be thrown).
- **React/Svelte reactivity:** a `useEffect` or `useCallback` dependency list that omits a value it reads (stale closure); a Svelte 5 `$effect` that reads reactive state only after an `await` or inside a `setTimeout`, since only reads made synchronously during the run are tracked.

## Trust boundaries

- Browser sources: `location` (search, hash, pathname), `document.referrer`, `window.name`, `localStorage`/`sessionStorage` (any script on the origin can write them), cookies, `postMessage` data (check `event.origin`), URL parameters, form fields, and file or clipboard content.
- Server sources: request URL, query, headers (including `Host` and `X-Forwarded-*`), body, cookies, uploaded file names and content; in SvelteKit that is `event.request`, `event.url`, `event.params` and form data in `+server.ts`, `+page.server.ts` actions and hooks. `load` functions in `+page.ts` and `+layout.ts` run in the browser as well, so secrets and private `$env` values must not be used there. Only variables with the public prefix (`PUBLIC_` by default) are exposed to client code through `$env/static/public` and `$env/dynamic/public`.
- Data from `JSON.parse`, `res.json()`, WebSocket messages and third-party APIs has the shape the sender chose, whatever the TypeScript type says.
- DOM and code sinks: `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write`, React `dangerouslySetInnerHTML`, Svelte `{@html ...}`, `eval`, `new Function`, `setTimeout("string")`, `javascript:` URLs in `href`/`src`, and `location.href = userValue`.
- Object keys from outside: `obj[key] = value`, recursive merge or `Object.assign` with `__proto__`, `constructor` or `prototype` keys can pollute `Object.prototype` (verified: a recursive merge of `JSON.parse('{"__proto__":{"polluted":1}}')` made `({}).polluted` equal `1`; `JSON.parse` alone creates an own property and does not pollute). Use `Map` or `Object.create(null)`, or reject those keys.
- Process and filesystem sinks in Node: `child_process.exec`/`execSync` with an interpolated string (use `execFile`/`spawn` with an argument array and no shell), `path.join`/`path.resolve` with a user-supplied segment (verified: `..` escapes the base), `fs` calls on user paths, `new RegExp(userInput)` (injection and catastrophic backtracking), and SQL built by string concatenation or template literals.
- Dependencies and install scripts: lockfile changes, `postinstall` scripts, and packages fetched from a URL or a git ref are untrusted code at install time.
