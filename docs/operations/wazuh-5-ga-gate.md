# Wazuh 5.0 GA gate

Branch: `upgrade/wazuh-5.0`
Gate implemented by: `lib/ga_gate.sh`, `scripts/check-ga-gate.sh`, `make ga-gate`
Coverage: `tests/lib/test_ga_gate.bats`

## Why this exists

Phase 7 of the 5.0 upgrade is gated on Wazuh publishing GA 5.0 packages *and*
the corresponding checksum set. Both halves of that condition used to be
tracked in prose — an issue description and a readiness audit — which is not
something a script can respect and which drifts the moment upstream moves.

`VERSION.json` is the only assertion in this repository that a Wazuh version
is supported. The gate makes the condition that authorises editing it
checkable:

```bash
make ga-gate
```

Exit status 0 means all three checks passed and the pin may move. Anything
else, including an unreachable upstream, means `GATE CLOSED`.

## The three checks

| # | Check | Evidence |
|---|-------|----------|
| 1 | GA release published for the exact target version | `GET /repos/wazuh/wazuh/releases/tags/v<target>` returns `tag_name` == `v<target>`, `draft: false`, `prerelease: false` |
| 2 | Stable channel for the major line is checksummed | `https://packages.wazuh.com/<major>.x/apt/dists/stable/Release` serves a `SHA256:` or `SHA512:` section with at least one digest |
| 3 | Target version is installable from that channel | `.../dists/stable/main/binary-amd64/Packages` lists `wazuh-manager`, `wazuh-indexer`, `wazuh-dashboard` and `wazuh-agent` at the target version |

Design notes worth keeping:

- The tag match is exact and quoted, so `v5.0.0-beta5` can never satisfy a
  `v5.0.0` target.
- The package index is consulted for the *stable* channel only. A release
  candidate published to `packages-staging.xdrsiem.wazuh.info` does not open
  this gate, which is why the staging repository is not probed.
- All four managed packages are required. A channel that publishes only
  `wazuh-manager` is not a deployable release.
- A pre-release target is refused before any network request.
- Transport failures, HTTP 403 and empty bodies all fail closed.

## Recorded verdict — 2026-09-26

**GATE CLOSED (0/3).** Wazuh 5.0 is not GA.

| Check | Result | Observed |
|-------|--------|----------|
| GA release `v5.0.0` | fail | `GET .../releases/tags/v5.0.0` → HTTP 404. Newest 5.0 artifact is `v5.0.0-beta5` (1 Sep 2026), `prerelease: true`. Newest GA is `v4.14.8` (25 Sep 2026). |
| Checksummed `5.x` stable channel | fail | `GET https://packages.wazuh.com/5.x/apt/dists/stable/Release` → HTTP 403 `AccessDenied`. The `4.x` control request returns 200, so this is an unpublished channel rather than a probe failure. |
| `5.0.0` in the stable channel | fail | Follows from the above; the channel does not exist. |

The `5.0.0` entries on the release-notes index that motivated this ticket are
no longer present at all, and `4.14.8` has been published since. The pin in
`VERSION.json` stays where it is.

## Residual risks — assumptions that could not be verified against a GA release

These are the 5.0 assumptions carried by the branch. None of them has been
exercised against a GA artifact, because no GA artifact exists. Each stays on
this list until a live canary against a real 5.0 package run clears it.

| Assumption | Cleared by |
|------------|------------|
| Manager install path `/var/wazuh-manager`, config `wazuh-manager.conf`, owner/group `wazuh-manager` are correct for 5.0 GA | Live canary: install 5.0 GA, confirm paths and service account |
| 5.x drops Filebeat for native server → indexer event shipping | Live canary: confirm alert pipeline without Filebeat; confirm the indexer-connector path exists |
| 5.0 publishes `artifact_urls.yaml` (not the 4.x `.yml`) with a per-stage manifest selected by `stage` in `VERSION.json` | Re-run `scripts/update-checksums.sh` against GA artifacts |
| Pre-release builds resolve from `packages-staging.xdrsiem.wazuh.info/pre-release/<major>.x/`, GA from `packages.wazuh.com/<major>.x/` | GA canary run; the stable-channel URLs in the role defaults must resolve |
| OpenSearch 3.x index patterns, ISM policies and the security model rebuild cleanly from the 4.x data | Canary restore test against a production-shaped dataset |
| Dashboard saved objects are portable, or a documented re-import is required | Canary dashboard verification by QA |
| `wazuh-analysisd` loads the custom rules, decoders, CDB lists and SCA policies and produces expected alerts | Rule-fixture run under `analysisd` with representative logs |
| Certificate layout, API authentication and the single-token enrolment path are unchanged from 4.x | Canary: enrol and upgrade an agent, verify API auth |
| `stage` values beyond `stable` (`rc1`, `beta5`) map to real upstream manifest directories | GA run; the stage → manifest mapping is currently inferred from rc1 |
| Backup and restore of a 5.0 manager, indexer and dashboard is lossless | Canary backup → destroy → restore drill |

Two environment constraints are also unresolved and are *not* upstream risks:

- The runner has Docker installed but cannot reach `/var/run/docker.sock`, so
  the containerised canary cannot execute here. That is an environment
  blocker, not a failed test.
- `analysisd` detection coverage is still 0/0: `tests/rules/run_rule_tests.sh`
  runs but has no `.log` fixtures.

## Flipping the pin

Only after `make ga-gate` exits 0, on the `upgrade/wazuh-5.0` branch:

1. `VERSION.json` → `{"version": "<target>", "stage": "stable"}`
2. `make ga-gate` re-run to confirm it still passes for the new pin
3. `make test`
4. Re-run `scripts/update-checksums.sh` so the pinned checksums match GA
   artifacts
5. Re-run the readiness audit and move every cleared assumption out of the
   table above

Merging to `main` is explicitly *not* part of this step.
