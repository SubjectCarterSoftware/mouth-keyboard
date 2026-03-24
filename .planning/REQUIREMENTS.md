# Requirements: v1.4 Hold-to-Transcribe Permission Fix

**Defined:** 2026-03-24
**Core Value:** From a single hotkey, the user can dictate and get reliable text into the clipboard fast enough that it feels close to typing speed.

## v1.4 Requirements

Requirements for this milestone. Each maps to roadmap phases.

### Permission Wiring

- [ ] **HTT-01**: Hold to Transcribe row in Settings checks Input Monitoring permission status (`CGPreflightListenEventAccess`), not Accessibility
- [ ] **HTT-02**: Clicking "Enable" on the Hold to Transcribe row requests Input Monitoring permission (`CGRequestListenEventAccess`)
- [x] **HTT-03**: Recovery action from a denied Hold to Transcribe row opens Privacy > Input Monitoring, not Privacy > Accessibility

### User-Facing Text

- [ ] **HTT-04**: All user-facing labels and descriptions in the Hold to Transcribe row reference "Input Monitoring", not "Accessibility"
- [ ] **HTT-05**: Setup guide popover shows steps for adding the app to Privacy > Input Monitoring

### Permission Model

- [x] **HTT-06**: `PermissionKind` includes a `.keyboard` case with the correct `settingsURL` for `Privacy_ListenEvent`
- [x] **HTT-07**: `.postEvent` permission messages reference only Auto Paste — no mention of Hold to Transcribe

### Test and Verification

- [ ] **HTT-08**: Existing UI tests are updated to assert the corrected Input Monitoring strings
- [x] **HTT-09**: Toggle/tap activation, Auto Paste permission flow, and all unrelated features remain unchanged
- [ ] **HTT-10**: Hold mode functions end-to-end when Input Monitoring is granted (manual verification — requires system permission)

## Future Requirements

- **HTT-F01**: `ReadinessSnapshot.derive()` gains a `keyboardStatus` parameter for full permission model coverage
- **HTT-F02**: Permission checklist on setup landing page shows an Input Monitoring tile
- **HTT-F03**: `HoldToTranscribeMonitor` retries tap creation on app foreground after permission grant

## Out of Scope

| Feature | Reason |
|---------|--------|
| ReadinessSnapshot keyboard status parameter | Increases scope beyond wiring fix; follow-up milestone |
| Permission checklist Input Monitoring tile | Coupled to ReadinessSnapshot change; defer together |
| Monitor retry-on-foreground | UX improvement beyond the permission wiring fix |
| Changes to HotkeyService, HoldToTranscribeMonitor, ActivationStore | Underlying hold logic is correct — only UI wiring is broken |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| HTT-01 | Phase 20 | Pending |
| HTT-02 | Phase 20 | Pending |
| HTT-03 | Phase 20 | Complete |
| HTT-04 | Phase 20 | Pending |
| HTT-05 | Phase 20 | Pending |
| HTT-06 | Phase 20 | Complete |
| HTT-07 | Phase 20 | Complete |
| HTT-08 | Phase 21 | Pending |
| HTT-09 | Phase 20, 21 | Complete |
| HTT-10 | Phase 21 | Pending |

**Coverage:**
- v1.4 requirements: 10 total
- Mapped to phases: 10
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-03-24 after initial definition*
