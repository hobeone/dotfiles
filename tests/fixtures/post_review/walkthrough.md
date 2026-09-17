<details>
<summary>📝 Walkthrough</summary>

## Walkthrough

Adds two small Go files and removes a stale one, exercising the
inline/orphan/deleted-file paths of the review test fixtures.

### Changes

**Fixture files**

|Layer / File(s)|Summary|
|---|---|
|**source** <br> `a.go`, `b.go`|Add trivial functions used as anchor targets.|
|**cleanup** <br> `old.go`|Remove a stale file to exercise the deleted-file path.|

**Estimated code review effort:** 1 (Trivial) | ~2 minutes

**Merge Risk:** _🟢 Low_ · up to `abc123`

Nothing blocks this merging as-is; it is test fixture data only.

</details>
