# 1.0 content and schema freeze (#43)

Do this after the balance sweep (#28), not before.

## Audit

- Headless `tests/content_validation` is green
- Every job, perk, module, upgrade, event is referenced or explicitly accepted as unused
- No broken `unlock_achievement` / effect target paths

## Freeze

1. Stop adding new content IDs
2. Leave `RunState.SAVE_VERSION` at the current value unless a migration is required
3. Bump `application/config/version` in `project.godot` to `1.0.0`
4. Bump Android `version/name` to `1.0.0` and increment `version/code`
5. Update `site/src/lib/site.ts` version

Until that bump, the game remains **0.7.1**.
