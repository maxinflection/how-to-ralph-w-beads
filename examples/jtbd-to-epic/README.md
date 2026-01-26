# JTBD to Epic Conversion Example

This example shows how to convert a Job-to-be-Done (JTBD) into a beads epic with child tasks.

## Example JTBD

**"Help designers create mood boards"**

## Step 1: Break JTBD into Topics of Concern

A JTBD typically breaks down into several topics of concern:

| Topic | Description |
|-------|-------------|
| Image Collection | Gathering and uploading images |
| Color Extraction | Analyzing images for color palettes |
| Layout | Arranging elements on the board |
| Sharing | Exporting and collaborating |

Each topic becomes a candidate for an epic or major task.

## Step 2: Create the Epic

```bash
bd create --title="Epic: Mood Board Creation" --type=epic --priority=1 \
  --description="
## JTBD
Help designers create mood boards for client presentations and personal inspiration.

## Topics of Concern
1. Image Collection - upload and organize reference images
2. Color Extraction - analyze images for color palettes
3. Layout - arrange elements visually
4. Sharing - export and collaborate

## Success Criteria
- Designer can create a complete mood board from start to finish
- Boards can be shared with clients
- Color palettes are automatically extracted
"
```

This returns the epic ID, e.g., `bd-a1b2`.

## Step 3: Create Child Tasks

### Task 1: Image Upload

```bash
bd create --title="Implement image upload" --type=task --priority=1 \
  --parent=bd-a1b2 \
  --description="
## Context
First step in mood board creation - users need to upload reference images.

## References
- src/components/Upload/
- docs/file-handling.md

## Approach
1. Create UploadDropzone component
2. Handle drag-and-drop and file picker
3. Validate file types (jpg, png, webp)
4. Store in S3 with signed URLs
5. Show upload progress
" \
  --acceptance="
- [ ] Upload accepts jpg/png/webp | \`npm test -- --grep 'upload accepts'\` | exit 0
- [ ] Drag and drop works | \`npm run e2e -- --grep 'drag drop'\` | exit 0
- [ ] Progress indicator shows | \`npm test -- --grep 'progress'\` | exit 0
- [ ] Files stored in S3 | \`npm test -- --grep 's3 upload'\` | exit 0
"
```

Returns: `bd-a1b2.1`

### Task 2: Color Extraction

```bash
bd create --title="Implement color extraction" --type=task --priority=1 \
  --parent=bd-a1b2 \
  --description="
## Context
After images are uploaded, extract dominant colors for palette suggestions.

## References
- src/lib/color-utils.ts
- docs/color-algorithms.md

## Approach
1. Use canvas to sample image pixels
2. Implement k-means clustering for dominant colors
3. Return 5-8 colors per image
4. Convert to various formats (hex, rgb, hsl)
" \
  --acceptance="
- [ ] Extracts 5-8 colors | \`npm test -- --grep 'extract colors'\` | exit 0
- [ ] Handles edge cases (grayscale, transparent) | \`npm test -- --grep 'edge case'\` | exit 0
- [ ] Returns multiple formats | \`npm test -- --grep 'color format'\` | exit 0
"
```

Returns: `bd-a1b2.2`

### Task 3: Layout Editor

```bash
bd create --title="Implement layout editor" --type=task --priority=2 \
  --parent=bd-a1b2 \
  --description="
## Context
Users need to arrange uploaded images and color swatches on a canvas.

## References
- src/components/Canvas/
- docs/layout-system.md

## Approach
1. Use react-dnd for drag-drop
2. Implement snap-to-grid
3. Support resize handles
4. Auto-save layout changes
" \
  --acceptance="
- [ ] Items can be dragged | \`npm run e2e -- --grep 'drag item'\` | exit 0
- [ ] Items can be resized | \`npm run e2e -- --grep 'resize'\` | exit 0
- [ ] Layout auto-saves | \`npm test -- --grep 'auto save'\` | exit 0
"
```

Returns: `bd-a1b2.3`

### Task 4: Export/Share

```bash
bd create --title="Implement export and sharing" --type=task --priority=2 \
  --parent=bd-a1b2 \
  --description="
## Context
Completed mood boards need to be shareable with clients.

## References
- src/api/share/
- docs/export-formats.md

## Approach
1. Generate shareable link (read-only view)
2. Export as PNG/PDF
3. Copy color palette as CSS/Tailwind
" \
  --acceptance="
- [ ] Shareable link works | \`npm test -- --grep 'share link'\` | exit 0
- [ ] PNG export generates | \`npm test -- --grep 'export png'\` | exit 0
- [ ] PDF export generates | \`npm test -- --grep 'export pdf'\` | exit 0
"
```

Returns: `bd-a1b2.4`

## Step 4: Wire Dependencies

Some tasks depend on others:

```bash
# Color extraction needs images to analyze
bd dep add bd-a1b2.2 bd-a1b2.1

# Layout needs images and colors to arrange
bd dep add bd-a1b2.3 bd-a1b2.1
bd dep add bd-a1b2.3 bd-a1b2.2

# Export needs a complete layout
bd dep add bd-a1b2.4 bd-a1b2.3
```

## Step 5: Verify the Structure

```bash
# View the dependency tree
bd list --parent=bd-a1b2

# Check what's ready to work on
bd ready

# Should show: bd-a1b2.1 (Image upload) as the only ready task
```

## Result

The dependency graph now looks like:

```
bd-a1b2 (Epic: Mood Board Creation)
├── bd-a1b2.1 (Image upload) ← READY
├── bd-a1b2.2 (Color extraction) ← blocked by .1
├── bd-a1b2.3 (Layout editor) ← blocked by .1, .2
└── bd-a1b2.4 (Export/share) ← blocked by .3
```

The agent will:
1. Pick bd-a1b2.1 first (only ready task)
2. After closing it, bd-a1b2.2 becomes ready
3. After closing .2, bd-a1b2.3 becomes ready
4. After closing .3, bd-a1b2.4 becomes ready
5. After closing .4, the epic can be closed

This ensures work proceeds in the correct order without explicit orchestration.
