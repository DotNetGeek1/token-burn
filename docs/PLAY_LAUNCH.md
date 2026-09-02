# Launch runbook (#46)

Blocked until [#45](https://github.com/DotNetGeek1/token-burn/issues/45) closed-test days have elapsed.

## Before production apply

- [ ] Closed test: 12 opted-in testers, 14 continuous days
- [ ] Privacy policy live (`/privacy` on the promo site) and linked in Play Console (#29)
- [ ] Data safety form matches [DATA_SAFETY.md](DATA_SAFETY.md)
- [ ] Content rating questionnaire complete
- [ ] Store listing assets accepted (#30 / [STORE_LISTING.md](STORE_LISTING.md))
- [ ] Pre-launch report reviewed; no release-blocking crashes
- [ ] RC smoke from a Play-delivered build ([RELEASE_CANDIDATE.md](RELEASE_CANDIDATE.md))

## Staged rollout

1. 20% of production for 24 hours
2. 50% if crash-free and no P0 reports
3. 100%

## Stop / rollback

Stop the rollout (do not halt the current percentage unless Play requires it; pause further expansion) if any of:

- Crash rate or ANR rate is worse than the closed-track baseline
- Save corruption or cannot-progress reports on more than one device
- Play policy rejection / Data safety mismatch

Rollback: upload the last known-good AAB with a higher `version/code`. Do not reuse a version code.

## Support contact

- Email: use the Play Console support email (set before production)
- Site: https://tokenburn.dotnetgeek.co.uk

## Release notes template

```
Token Burn 1.0
Take software jobs, build unstable pipelines, and burn absurd quantities of tokens.
This release is the first production build on Google Play.
```
