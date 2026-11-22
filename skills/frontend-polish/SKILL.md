---
name: frontend-polish
description: "웹 사이트·웹 앱 프론트 결과물(페이지, 랜딩, 대시보드, 컴포넌트 화면)을 새로 만들거나 다듬을 때 사용한다. 구현을 위임하기 전, 직접 구현하기 전에 읽는다. Figma 링크가 기준이면 figma-fidelity 를 우선한다. (frontend polish)"
---

# Frontend polish

The target is a page that reads as *clean* at rest and feels *alive* in use: a quiet layout carrying rich, purposeful motion.

## 1. Delegate at full strength
- When implementation goes to a subagent or worker, set the model to Opus 5.5 or Fable 5.2 (`opus` / `fable`) and effort to `max`, and pass this skill's name in its spec.
- When this session builds it directly, build it here as is; the session's own model and effort are the user's choice.

## 2. Layout: clean
- Few colors, one type scale, generous whitespace, a consistent spacing step, aligned edges.
- Reuse the project's design system and components first; add an element only when the content needs it.

## 3. Motion: as rich as the style carries
- Give every interaction its motion: page and route transitions, staggered entrance of content, hover and press feedback, scroll-linked reveals, state changes (open, close, load, success, error).
- Match intensity and speed to the page's style: calm pages get short, soft easing; playful pages may go further. Motion serves reading: content stays readable and clickable at every frame, and nothing loops without the user's action.
- Animate `transform` and `opacity`; use the project's installed animation library, else CSS and the Web Animations API.
- Under `prefers-reduced-motion: reduce`, replace movement with instant or fade-only changes.

## 4. Done
- Open the page in a browser at desktop and mobile widths, and walk every interaction once.
- Done means: no layout shift or overflow at either width, every listed motion plays and ends cleanly, and reduced-motion mode shows the same content without movement. Report what you checked and what you did not.
