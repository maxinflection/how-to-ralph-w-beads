# Pattern 3: Existence Checks

Verify files, exports, or patterns exist in the codebase.

## When to Use

- Structural requirements (file must exist)
- Export verification (component exported from index)
- Route registration
- Configuration presence
- Migration creation

## Format

```
- [ ] {what should exist} | `{check command}` | exit 0
```

## Examples

### File Existence

```markdown
- [ ] Component file exists | `test -f src/components/Button.tsx` | exit 0
- [ ] Test file exists | `test -f src/components/Button.test.tsx` | exit 0
- [ ] Config file present | `test -f config/production.json` | exit 0
- [ ] Migration created | `ls db/migrations/*create_users* 2>/dev/null` | exit 0
```

### Directory Structure

```markdown
- [ ] Feature directory created | `test -d src/features/auth` | exit 0
- [ ] Has required subdirs | `test -d src/features/auth/components && test -d src/features/auth/hooks` | exit 0
```

### Export Verification

```markdown
- [ ] Component exported from index | `grep -q "export.*Button" src/components/index.ts` | exit 0
- [ ] Type exported | `grep -q "export type.*UserProps" src/types/index.ts` | exit 0
- [ ] Function exported | `grep -q "export function.*validateEmail" src/utils/index.ts` | exit 0
```

### Route/Endpoint Registration

```markdown
- [ ] Route registered | `grep -q '"/api/users"' src/routes.ts` | exit 0
- [ ] Middleware applied | `grep -q "authMiddleware" src/routes/protected.ts` | exit 0
- [ ] Handler connected | `grep -q "userController.create" src/routes/users.ts` | exit 0
```

### Git Hooks

```markdown
- [ ] Pre-commit hook installed | `test -x .git/hooks/pre-commit` | exit 0
- [ ] Husky configured | `test -f .husky/pre-commit` | exit 0
```

### Package.json Scripts

```markdown
- [ ] Build script exists | `jq -e '.scripts.build' package.json` | exit 0
- [ ] Test script configured | `jq -e '.scripts.test' package.json` | exit 0
```

## Tips

1. **Use `test -f` for files** - More portable than `[ -f ]`
2. **Use `test -d` for directories** - Clear intent
3. **Use `test -x` for executables** - Checks both existence and permission
4. **Combine with `&&`** - Check multiple conditions

## Common Patterns

### Check file exists and is not empty

```markdown
- [ ] Config has content | `test -s config/settings.json` | exit 0
```

### Check pattern appears N times

```markdown
- [ ] All routes have auth | `grep -c "requireAuth" src/routes/*.ts | awk '$1 >= 5'` | exit 0
```

### Check file does NOT exist (cleanup verification)

```markdown
- [ ] Temp files cleaned | `test ! -f tmp/cache.json` | exit 0
```
