---
id: TASK-1
title: Resize window direction arrows
status: To Do
assignee: []
created_date: '2026-08-21 13:28'
labels: []
dependencies: []
ordinal: 1000
---
### Goal

Add keyboard-driven, context-aware resizing that feels like modifier + WASD/arrow keys. The requested direction is always the user’s intent; Rectangle determines whether that means expand, contract, transition to another placement, swap windows, or safely no-op.

### Shortcuts

Add configurable Extra Shortcuts near the existing split/cyclic resize shortcuts:

- `Resize Up`
- `Resize Down`
- `Resize Left`
- `Resize Right`
- `Max Resize Up`
- `Max Resize Down`
- `Max Resize Left`
- `Max Resize Right`

Regular resize moves one cyclic ratio step. Max resize jumps to the farthest achievable ratio in the same direction. Both use the same placement and intent resolver.

### Placement and direction model

Classify the focused window as:

- `topLeftCorner`
- `topRightCorner`
- `bottomLeftCorner`
- `bottomRightCorner`
- `leftSide`
- `rightSide`
- `topSide`
- `bottomSide`
- `floatingOrAmbiguous`

Use Rectangle’s existing visible-frame and placement tolerances.

For corner windows:

| Placement | Expand directions | Contract directions |
| --- | --- | --- |
| Top-left | Right, Down | Left, Up |
| Top-right | Left, Down | Right, Up |
| Bottom-left | Right, Up | Left, Down |
| Bottom-right | Left, Up | Right, Down |

For side windows:

| Placement | Expand | Contract | Perpendicular navigation |
| --- | --- | --- | --- |
| Left side | Right | Left | Up → top-left; Down → bottom-left |
| Right side | Left | Right | Up → top-right; Down → bottom-right |
| Top side | Down | Up | Left → top-left; Right → top-right |
| Bottom side | Up | Down | Left → bottom-left; Right → bottom-right |

Up/down always affect height and the horizontal internal boundary. Left/right always affect width and the vertical internal boundary. The configured cyclic axis must never redirect the requested direction onto another axis.

### Ratio behavior

Use the existing ordered cyclic ratios, normally:

- `1/4`
- `1/3`
- `1/2`
- `2/3`
- `3/4`

Requirements:

- Regular expansion selects the next larger ratio.
- Regular contraction selects the next smaller ratio.
- Max expansion selects the largest achievable ratio.
- Max contraction selects the smallest achievable ratio.
- An achieved ratio between presets moves to the next preset in the requested direction.
- Use tolerance to avoid repeatedly selecting the same ratio because of rounding.
- Do not wrap from maximum to minimum or minimum to maximum.
- Constraints must never reverse the requested direction.
- If no movement is possible in the requested direction, safely no-op.

### Endpoint navigation

Corner expansion must reach its maximum achievable ratio before any placement transition occurs.

- Regular resize steps through every configured cyclic ratio.
- Max resize jumps to the maximum.
- Neither action may promote or swap while further expansion is available.
- Once the corner is already at its maximum, the next expansion command performs the appropriate transition.
- A maximum constrained by window minimum sizes counts as the endpoint.
- Determine endpoints from the achieved frame, not only exact nominal ratio equality.
- Contraction at its minimum remains a no-op and never promotes.

Normal endpoint transitions are:

- Top-left + Right → top side
- Top-right + Left → top side
- Bottom-left + Right → bottom side
- Bottom-right + Left → bottom side
- Top-left + Down → left side
- Bottom-left + Up → left side
- Top-right + Down → right side
- Bottom-right + Up → right side

A subsequent perpendicular command from the side can place the window into the adjacent corner.

### Relationship to the cyclic expansion axis

Commands parallel to the configured cyclic expansion axis retain the existing cyclic, promotion, cooperative-resize, and side-placement behavior.

Commands perpendicular to the cyclic expansion axis require an additional corner-alignment check:

- Vertical cyclic expansion: left/right commands are perpendicular; compare the adjacent corners’ heights and horizontal boundaries.
- Horizontal cyclic expansion: up/down commands are perpendicular; compare the adjacent corners’ widths and vertical boundaries.

This check only occurs after the focused corner has reached its maximum expansion endpoint.

#### Aligned adjacent corners

If the relevant cyclic-axis ratios and boundaries match within tolerance:

- Preserve the existing `corner → side → adjacent corner` flow.
- The side remains an intermediary placement.
- Do not use the direct-swap path.
- Continue using the normal cooperative and side-split behavior.

#### Mismatched adjacent corners

If the ratios or boundaries do not match:

- Do not expand the focused window across the side over another window.
- Skip the side intermediary.
- Identify the unique window occupying the requested adjacent corner.
- Directly exchange the two windows’ complete original frames:
  - the focused window adopts the adjacent window’s original frame and size;
  - the adjacent window adopts the focused window’s original frame and size.
- Only these two windows participate in the swap.
- Do not require a complete four-window grid.
- Do not resize complementary neighbors or broadly capture unrelated windows.
- Preserve existing gaps by exchanging the original frames exactly.

Examples:

- Vertical cyclic expansion, top-right moving left:
  - Continue expanding through horizontal cyclic ratios until maximum.
  - If top-right and top-left heights align, transition through top side.
  - If their heights differ, swap the top-right and top-left window frames.
- Horizontal cyclic expansion, bottom-left moving up:
  - Continue expanding through vertical cyclic ratios until maximum.
  - If bottom-left and top-left widths align, transition through left side.
  - If their widths differ, swap their complete frames.

The behavior must be symmetric for all four corners and both cyclic-axis configurations.

### Side-to-corner displacement

When the normal aligned path moves a side window into an occupied corner:

- Move displaced adjacent windows into the originating corner region at the smallest valid complementary cyclic size.
- Do not leave an avoidable blank region behind.
- Respect each window’s actual minimum size.
- Do not push a window outside the visible frame, into a configured gap, or over another window.
- If a valid layout cannot be produced, safely no-op or roll back instead of applying a partial layout.

This displacement behavior does not apply to mismatched-ratio direct swaps, which exchange exactly two original frames.

### Cooperative resizing

For ordinary resize, promotion, and aligned side-to-corner placement:

- When cooperative resizing is enabled, resize windows sharing the moved internal boundary.
- When disabled, resize only the focused window.
- Preserve configured gaps.
- Respect minimum sizes and screen bounds.
- Avoid capturing unrelated nearby windows more aggressively than Rectangle’s existing cooperative planner.

A mismatched-ratio direct swap inherently affects the focused and target windows regardless of the cooperative-resize preference, but no additional windows should be captured.

### Swap safety and atomicity

Before applying a direct swap:

- Require exactly one valid target-corner occupant.
- Require both destination frames to be within the visible screen.
- Verify each window can fit the other window’s original frame.
- Respect configured and reported minimum sizes.
- Verify the resulting frames do not overlap improperly.

Apply the swap atomically:

- Move both windows.
- Verify their achieved frames.
- If either window rejects its frame or the result is unsafe, restore both original frames.
- Update history and active ratios only after successful verification.
- Never leave multiple windows assigned to one frame.
- Never allow a failed action to collapse the layout, move windows offscreen, or make windows disappear.

### Active split ratios

After a successful resize or placement:

- Update runtime/local active ratios from the achieved frames.
- Never derive them only from the requested preset when constraints changed the result.
- Update only the boundary affected by the command.
- Do not write runtime ratios back to saved/default preferences.
- No-op and rolled-back actions must not update ratios.

For a mismatched two-window swap:

- Update the shared perpendicular placement boundary from the verified result.
- Preserve the existing mismatched cyclic-axis ratios for the individual rows or columns.

### Floating or ambiguous windows

If placement can be confidently inferred from the current frame, apply the same directional rules. If placement or the intended adjacent target is ambiguous, prefer a safe no-op.

### Implementation guidance

- Keep one shared resolver for regular and max resize.
- Resolve placement and direction before invoking layout code.
- The resolved intent should include:
  - axis;
  - expand, contract, transition, swap, or no-op;
  - internal boundary;
  - movement direction;
  - step or max target mode;
  - endpoint action.
- Reuse the existing cyclic ratio list, active split-ratio model, placement actions, and cooperative planner.
- Do not create another source of truth for layout or split state.

### Acceptance criteria

- All eight shortcuts are configurable.
- Direction interpretation is consistent between regular and max resize.
- Regular resize traverses cyclic ratios one step at a time.
- Max resize jumps to the farthest achievable endpoint.
- Expansion reaches maximum before promotion or swapping.
- Minimum-size-constrained endpoints promote on the next invocation.
- Contraction at minimum safely no-ops.
- Parallel-axis behavior remains unchanged.
- Aligned perpendicular movement retains the side intermediary.
- Mismatched perpendicular movement swaps exactly two complete window frames.
- Side-to-corner movement fills the originating region without violating gaps or minimum sizes.
- Failed or unsafe operations leave the entire layout unchanged.
- Runtime ratios reflect verified achieved layouts.
- Saved preferences remain unchanged.
- Existing cyclic, cooperative, side/corner, dynamic-split, and shortcut behavior continues to pass

