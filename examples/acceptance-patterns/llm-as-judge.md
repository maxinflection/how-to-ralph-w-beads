# Pattern 4: LLM-as-Judge

For subjective criteria that resist programmatic validation.

## When to Use

- Creative quality (writing tone, engagement)
- Aesthetic judgments (visual design, UI balance)
- UX quality (intuitiveness, clarity)
- Content appropriateness (messaging, audience fit)
- Documentation clarity

## Format

```
- [ ] {what to evaluate} | `MANUAL` | LLM review confirms: {specific criteria}
     Artifact: {file or output to review}
     Rubric:
       1. {criterion 1}
       2. {criterion 2}
```

## Examples

### Writing/Content Quality

```markdown
- [ ] Error messages are user-friendly | `MANUAL` | LLM review confirms helpfulness
     Artifact: src/messages/errors.ts
     Rubric:
       1. Each message explains what went wrong in plain language
       2. Each message suggests a specific action to resolve
       3. No technical jargon or stack traces exposed to users
       4. Tone is helpful, not blaming
```

### Documentation Clarity

```markdown
- [ ] README is understandable | `MANUAL` | LLM review confirms clarity
     Artifact: README.md
     Rubric:
       1. Purpose is clear within first paragraph
       2. Setup instructions are complete and sequential
       3. No assumed knowledge beyond stated prerequisites
       4. Examples are runnable as-is
```

### UI/UX Quality

```markdown
- [ ] Dashboard has clear hierarchy | `MANUAL` | LLM review confirms visual organization
     Artifact: screenshot of /dashboard (save to tmp/dashboard.png)
     Rubric:
       1. Primary action is immediately obvious
       2. Related items are visually grouped
       3. Navigation is discoverable
       4. No more than 3 levels of visual importance
```

### Tone/Voice Consistency

```markdown
- [ ] Onboarding flow feels welcoming | `MANUAL` | LLM review confirms tone
     Artifact: src/onboarding/*.tsx (all copy text)
     Rubric:
       1. Conversational but professional
       2. Encouraging without being condescending
       3. Consistent voice across all steps
       4. Clear progress indicators
```

### Code Quality (Beyond Lint)

```markdown
- [ ] Code follows team patterns | `MANUAL` | LLM review confirms consistency
     Artifact: src/features/new-feature/
     Rubric:
       1. File structure matches existing features
       2. Naming conventions followed
       3. Error handling patterns consistent
       4. Comments explain "why" not "what"
```

## How to Verify in Build Mode

Since these are marked `MANUAL`, the build agent should:

1. **Read the artifact** specified in the criterion
2. **Apply the rubric** - evaluate each point
3. **Document the review** in the close reason:

```markdown
bd close <id> --reason "
Verified:
- [x] Error messages user-friendly (MANUAL - LLM review)
      Reviewed src/messages/errors.ts:
      1. Plain language: YES - uses "couldn't find" not "404 NOT_FOUND"
      2. Actionable: YES - each message includes "Try..." suggestion
      3. No jargon: YES - no error codes or stack traces
      4. Helpful tone: YES - apologetic without over-explaining
"
```

## Tips

1. **Be specific in rubrics** - "friendly" is vague; "no jargon" is verifiable
2. **Limit rubric to 3-5 points** - More becomes unwieldy
3. **Reference artifacts explicitly** - Don't rely on context
4. **Binary criteria work best** - Each rubric point should be YES/NO

## When NOT to Use

Don't use LLM-as-judge for things that can be programmatically verified:

```markdown
# Bad - can be checked with lint/test
- [ ] Code is clean | `MANUAL` | ...

# Good - use actual tools
- [ ] Code passes lint | `npm run lint` | exit 0
```

Reserve LLM-as-judge for genuinely subjective qualities where human judgment is required.
