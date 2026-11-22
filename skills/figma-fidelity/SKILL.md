---
name: figma-fidelity
description: "Figma 링크(figma.com/design URL, node id)를 기준으로 UI를 구현·수정·리뷰·검증할 때 사용한다. get_design_context 호출 전, Figma를 인용하는 이슈·작업 지시 작성 전, 완료 판정 전에 읽는다. Figma와 무관한 UI 작업에는 사용하지 않는다. (figma fidelity)"
---

# Figma fidelity

Most Figma mismatches (color, font, gap, radius, placement) come from values carried by memory or prose and "done" judged by eye. These rules replace both with tool output and measurement.

## 1. Read: down to leaf nodes, with tools
- If the official `figma:figma-design-to-code` skill is installed, load it before any `get_design_context` call and follow it. Either way, the screenshot is the visual target, and a response flagged sparse is never implemented from: re-request the visible child nodes in parallel.
- A screen- or section-level link: call `get_metadata` first, then `get_design_context` on every visible leaf that carries style: text, table header/body cells, badges/chips, icons, buttons, inputs, dividers, card containers.
- Tokens come from `get_variable_defs` on the node. Never infer a token from a screenshot color or from a style name in an MCP summary.
- Text: use the DS typography token only when the Figma text node is bound to a Text Style. Unbound text uses its raw font-size, font-weight, line-height and letter-spacing.
- Note the frame width (e.g. 1440) — verification uses the same viewport.

## 2. Hand off: a node spec table, not a summary
- The one who received the link does not paraphrase it ("match Figma", "fix the spacing"). They write a spec table from step 1 and attach it to the issue and every worker spec (file path or inline):

| node id | element | text style / font (size/weight/line-height/tracking) | color token (fg/bg/border) | size (w×h) | padding / gap | radius | alignment / position | copy |
|---|---|---|---|---|---|---|---|---|

- Every row cites the MCP call it came from. Unknown values are written as 미확인, never guessed.
- Worker and reviewer specs must say: "Load the `figma-fidelity` skill (and `figma:figma-design-to-code` when installed); implement and verify against the spec table at <path>."

## 3. Implement: spec values win over component defaults
- Reuse shared components, but the rendered result must equal the spec table. If a shared component's default (padding, radius, font, color, highlight style) differs from Figma, fix it in the component or override it at the call site, and list it in the report as a shared-default mismatch.
- Use the repo's Figma token map (e.g. `docs/figma-token-map.md`) when it exists. A Figma value with no mapped token is reported, not replaced by the "closest" token.
- Check that class-merge helpers (e.g. tailwind-merge in `cn()`) do not strip typography or color classes; prefer static class strings where they do.
- Do not add elements, labels, badges or copy that the Figma node does not have.

## 4. Verify: a measured comparison table, or it is not done
- No Figma MCP in this session: stop and report that the design cannot be read; never implement from memory or a pasted image.
- Open the page in the repo's allowed browser at the Figma frame viewport, reach the state the frame shows (view and navigate only; never save, delete or submit on shared/production data).
- For every spec row, read the matching DOM element's `getComputedStyle` (font-size, font-weight, line-height, letter-spacing, color, background-color, border-color/width, border-radius, padding, gap) and `getBoundingClientRect` (width, height, and offsets to its neighbors), and write:

| node id | property | Figma | actual | match |
|---|---|---|---|---|

- Tolerance: size, spacing and position ±1px; color must be the same value (compare resolved rgb); font family/size/weight exact.
- Any mismatch → not done. Rows that could not be measured are listed as 미검증 with the reason; they are never counted as matched.
- The implementer puts this table in the report and PR. The reviewer re-measures at least the mismatched-before rows and a sample of others and states which rows were re-measured. The orchestrator never uses a scaled-down screenshot or "looks the same" as completion evidence.
