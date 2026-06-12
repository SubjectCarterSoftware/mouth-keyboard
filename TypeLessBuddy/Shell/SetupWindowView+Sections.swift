import SwiftUI

// MARK: - Settings sections

extension SetupWindowView {
    var permissionsSectionContent: some View {
        SettingsSectionCard(section: .permissions, flashTrigger: flashTrigger(for: .permissions)) {
            VStack(alignment: .leading, spacing: 16) {
                setupModelStatusContent
                PermissionChecklistView(
                    permissions: readinessStore.snapshot.permissions,
                    requestPermission: requestPermission,
                    openRecovery: openPermissionRecovery,
                    launchAtLoginEnabled: preferences.launchAtLogin,
                    onToggleLaunchAtLogin: { preferences.setLaunchAtLogin($0) },
                    usesGridLayout: true
                )
            }
        }
    }

    var generalSectionContent: some View {
        SettingsSectionCard(
            section: .general,
            flashTrigger: flashTrigger(for: .general)
        ) {
            SettingsSectionActionButton(
                title: "Restore Defaults",
                accessibilityIdentifier: "setupWindow.section.general.restoreDefaults"
            ) {
                restoreDefaultGeneralSettings()
            }
            .disabled(!isGeneralSectionCustomized)
        } content: {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    SetupFieldRow(title: "Microphone") {
                        MicPriorityPicker(
                            preferences: preferences,
                            audioDeviceService: audioDeviceService,
                            onOpenChange: { isMicPriorityPickerMenuOpen = $0 }
                        )
                        .frame(maxWidth: 240, alignment: .leading)
                    }
                    .zIndex(10)

                    SetupFieldRow(title: "Auto Paste") {
                        AlwaysAutoPasteRow(isOn: alwaysAutoPasteBinding)
                    }

                    SetupFieldRow(title: "Restore Clipboard") {
                        RestoreClipboardRow(
                            isOn: restorePreviousClipboardBinding,
                            isAutoPasteEnabled: preferences.alwaysAutoPaste
                        )
                    }

                    SetupFieldRow(title: "Play sound effects") {
                        PlaySoundEffectsRow(isOn: playSoundEffectsBinding)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    Text("Pill Position")
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .center)

                    PillPositionPickerRow(
                        selection: recordingPillPositionBinding,
                        onHoverChange: updatePillPositionPreview
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(width: 180, alignment: .center)
            }
        }
        .zIndex(isMicPriorityPickerMenuOpen ? 20 : 0)
    }

    var assistantSectionContent: some View {
        SettingsSectionCard(section: .assistant, flashTrigger: flashTrigger(for: .assistant)) {
            VStack(alignment: .leading, spacing: 14) {
                SetupFieldRow(title: "Assistant name") {
                    HStack(alignment: .center, spacing: 12) {
                        AssistantDisplayedNameChip(
                            name: assistantSettingsViewModel.displayedName,
                            isPreviewing: assistantSettingsViewModel.isPreviewingRecordedName
                        )
                        .accessibilityIdentifier("assistantRow.activeName")

                        Spacer(minLength: 12)

                        AIAssistantInlineRowView(
                            viewModel: assistantSettingsViewModel,
                            showsActiveName: false,
                            showsResetButton: false,
                            idleRecordButtonTitle: "Record Name"
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                SetupFieldRow(title: "Assistant system prompt") {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Assistant prompt used every time assistant is invoked")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Edit…") {
                            isShowingAssistantSystemPromptEditor = true
                        }
                        .frame(maxWidth: .infinity)
                        .frame(width: AssistantNameControlMetrics.recordControlWidth, alignment: .trailing)
                        .accessibilityIdentifier("setupWindow.rewriteSystemPrompt.open")
                    }
                }
            }
        }
    }

    var notesSectionContent: some View {
        SettingsSectionCard(section: .notes, flashTrigger: flashTrigger(for: .notes)) {
            VStack(alignment: .leading, spacing: 14) {
                SetupFieldRow(title: "Saving mode") {
                    NoteCaptureModeRow(mode: assistantNoteModeBinding)
                }

                SetupFieldRow(title: "Destination") {
                    if preferences.assistantNoteMode == .newFile {
                        AssistantNoteDestinationRow(
                            path: preferences.assistantNoteFolderPath,
                            placeholder: "No note folder selected",
                            destinationKind: .folder,
                            pathAccessibilityIdentifier: "setupWindow.notes.destination.path",
                            browseAccessibilityIdentifier: "setupWindow.notes.destination.browse",
                            clearAccessibilityIdentifier: "setupWindow.notes.destination.clear",
                            browseAction: chooseAssistantNoteFolder,
                            clearAction: { preferences.assistantNoteFolderPath = "" }
                        )
                    } else {
                        AssistantNoteDestinationRow(
                            path: preferences.assistantNoteAppendFilePath,
                            placeholder: "No append file selected",
                            destinationKind: .file,
                            pathAccessibilityIdentifier: "setupWindow.notes.destination.path",
                            browseAccessibilityIdentifier: "setupWindow.notes.destination.browse",
                            clearAccessibilityIdentifier: "setupWindow.notes.destination.clear",
                            browseAction: chooseAssistantNoteAppendFile,
                            clearAction: { preferences.assistantNoteAppendFilePath = "" }
                        )
                    }
                }
            }
        }
    }

    var historySectionContent: some View {
        SettingsSectionCard(
            section: .history,
            flashTrigger: flashTrigger(for: .history)
        ) {
            Toggle("Save history", isOn: Binding(
                get: { preferences.historyEnabled },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        preferences.historyEnabled = newValue
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.8, anchor: .trailing)
            .fixedSize()
            .accessibilityLabel("Save history")
            .accessibilityIdentifier("setupWindow.history.enabled")
        } content: {
            if preferences.historyEnabled {
                VStack(alignment: .leading, spacing: 14) {
                    SetupFieldRow(title: "History folder") {
                        HStack(alignment: .center, spacing: 8) {
                            HistoryFolderRow(
                                path: preferences.historyConfiguration.resolvedFolderPath,
                                placeholder: "No history folder selected",
                                showsResetAction: !preferences.historyFolderPath.isEmpty,
                                browseAction: chooseHistoryFolder,
                                resetAction: { preferences.historyFolderPath = "" }
                            )

                            Button(action: revealHistoryFolder) {
                                Image(systemName: "arrow.up.forward.app")
                                    .font(.body)
                            }
                            .buttonStyle(.borderless)
                            .help("Reveal in Finder")
                            .accessibilityIdentifier("setupWindow.history.reveal")
                        }
                    }

                    SetupFieldRow(title: "History storage limit", alignment: .top) {
                        HistoryStorageLimitRow(
                            storageLimitMB: Binding(
                                get: { preferences.historyStorageLimitMB },
                                set: { preferences.historyStorageLimitMB = $0 }
                            ),
                            usageText: historyVM.usageDescription
                        )
                    }

                    savedEntriesZone
                        .padding(.leading, SetupSectionMetrics.rowIndent)
                }
            }
        }
    }

    @ViewBuilder
    var savedEntriesZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved entries")
                    .font(.caption.weight(.bold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    isShowingClearHistoryConfirmation = true
                } label: {
                    Label("Clear history…", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(historyVM.entries.isEmpty)
                .accessibilityIdentifier("setupWindow.history.clearAll")
            }

            if let historyLoadError = historyVM.loadError {
                Text(historyLoadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if historyVM.entries.isEmpty {
                Text("No saved history entries in the current folder yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    TextField("Search transcriptions…", text: $historyVM.searchQuery)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("setupWindow.history.search")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.2))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(SetupColorPalette.controlBorder, lineWidth: 0.75)
                )

                HStack(alignment: .top, spacing: 12) {
                    historyList
                    HistoryDetailPane(
                        detail: historyVM.filteredSelectionDetail,
                        copyLabel: historyVM.copyConfirmationVisible ? "Copied" : "Copy",
                        copyAction: { historyVM.copySelectedEntry() },
                        revealAction: { if let url = historyVM.selectedEntryURL { revealHistoryEntry(url) } },
                        deleteAction: { if let url = historyVM.selectedEntryURL { historyVM.deleteEntry(url) } }
                    )
                    .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                ForEach(historyVM.groupedEntries, id: \.label) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            HistoryEntryRow(
                                entry: entry,
                                isSelected: historyVM.selectedEntryURL == entry.fileURL,
                                onSelect: { historyVM.selectEntry(entry.fileURL) },
                                onDelete: { historyVM.deleteEntry(entry.fileURL) }
                            )
                        }
                    } header: {
                        Text(group.label)
                            .font(.caption2.weight(.bold))
                            .tracking(0.4)
                            .textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .background(SetupColorPalette.cardBackground)
                    }
                }

                if historyVM.filteredEntries.isEmpty {
                    Text("No transcriptions match your search.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 18)
                }
            }
            .padding(.trailing, 4)
        }
        .frame(width: 220)
        .frame(minHeight: 230, maxHeight: 280)
        .accessibilityIdentifier("setupWindow.history.list")
    }

    var replacementsSectionContent: some View {
        SettingsSectionCard(
            section: .replacements,
            flashTrigger: flashTrigger(for: .replacements)
        ) {
            SettingsSectionActionButton(
                title: "Clear Mine…",
                accessibilityIdentifier: "setupWindow.section.replacements.clearAll"
            ) {
                isShowingClearAllReplacementsConfirmation = true
            }
            .disabled(!hasWordReplacements)
        } content: {
            ReplacementsSectionView(preferences: preferences)
        }
    }

    var shortcutsSectionContent: some View {
        SettingsSectionCard(
            section: .shortcuts,
            flashTrigger: flashTrigger(for: .shortcuts)
        ) {
            SettingsSectionActionButton(
                title: "Restore Defaults",
                accessibilityIdentifier: "setupWindow.section.shortcuts.restoreDefaults"
            ) {
                restoreDefaultKeyboardShortcuts()
            }
            .disabled(!isKeyboardShortcutsCustomized)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                SetupFieldRow(title: "Start recording") {
                    HStack(spacing: 12) {
                        KeyComboRecorder(name: .activate, preferences: preferences, onShortcutChanged: onTapShortcutChanged)
                        KeyComboRecorder(name: .activateAlt, preferences: preferences, onShortcutChanged: onTapShortcutChanged)
                        MouseButtonRecorder(
                            action: .startRecording,
                            preferences: preferences,
                            binding: preferences.startMouseButtonBinding,
                            accessibilityID: "setupWindow.activate.mouseRecorder",
                            onRecord: { binding in
                                preferences.startMouseButtonBinding = binding
                                HotkeyService.shared.configureMouseBindings()
                                onTapShortcutChanged()
                            },
                            onClear: {
                                preferences.startMouseButtonBinding = nil
                                HotkeyService.shared.configureMouseBindings()
                                onTapShortcutChanged()
                            }
                        )
                    }
                }

                SetupFieldRow(title: "Stop recording") {
                    HStack(spacing: 12) {
                        KeyComboRecorder(name: .stopSession, preferences: preferences, onShortcutChanged: onTapShortcutChanged)
                        KeyComboRecorder(name: .stopSessionAlt, preferences: preferences, onShortcutChanged: onTapShortcutChanged)
                        MouseButtonRecorder(
                            action: .stopRecording,
                            preferences: preferences,
                            binding: preferences.stopMouseButtonBinding,
                            accessibilityID: "setupWindow.stopSession.mouseRecorder",
                            onRecord: { binding in
                                preferences.stopMouseButtonBinding = binding
                                HotkeyService.shared.configureMouseBindings()
                                onTapShortcutChanged()
                            },
                            onClear: {
                                preferences.stopMouseButtonBinding = nil
                                HotkeyService.shared.configureMouseBindings()
                                onTapShortcutChanged()
                            }
                        )
                    }
                }

                KeyboardShortcutsRow(
                    preferences: preferences
                )
            }
        }
    }

    var advancedSectionContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isAdvancedSettingsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Text("Advanced")
                        .font(.title3.weight(.semibold))

                    Spacer()

                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isAdvancedSettingsExpanded ? 45 : 0))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("setupWindow.advancedDisclosure")

            if isAdvancedSettingsExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Speech Transcription Model")
                                .font(.body)

                            Spacer()

                            Text("Select a downloaded model. Use the icon to download it or remove its files.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        ForEach(WhisperModelChoice.allCases) { model in
                            whisperModelRow(for: model)
                        }

                        if case .failed(_, let message) = whisperModelLoadState.phase {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("Assistant Model")
                                .font(.body)

                            Spacer()

                            Text("Select a downloaded built-in local model, or use the cloud / localhost provider below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }

                        ForEach(RewriteModelTier.allCases) { tier in
                            rewriteModelRow(for: tier)
                        }

                        if case .failed(_, let message) = modelLoadState.phase {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        if !canManageRewriteModels {
                            Text("Wait for the current recording or transcription to finish before downloading, deleting, or switching assistant models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .opacity(preferences.cloudLLMConfig.isEnabled ? 0.5 : 1.0)
                    .disabled(preferences.cloudLLMConfig.isEnabled)

                    Divider()
                        .overlay(Color.white.opacity(0.08))

                    cloudLLMSettingsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .fill(SetupColorPalette.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsLayoutMetrics.cardCornerRadius, style: .continuous)
                .strokeBorder(SetupColorPalette.cardBorder, lineWidth: 1)
        )
        .modifier(
            SettingsCardFlashModifier(
                cornerRadius: SettingsLayoutMetrics.cardCornerRadius,
                flashTrigger: flashTrigger(for: .advanced)
            )
        )
        .accessibilityIdentifier("setupWindow.section.advanced")
    }

    var settingsBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("TypeLessBuddy Settings")
                        .font(.title2.weight(.semibold))
                        .accessibilityIdentifier("setupWindow.title")

                    Spacer()

                    Button("Guide") {
                        openGuide()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("setupWindow.guideButton")
                }

                ScrollViewReader { proxy in
                    HStack(alignment: .top, spacing: SettingsLayoutMetrics.contentSpacing) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(SettingsSection.allCases) { section in
                                SettingsSidebarButton(
                                    section: section,
                                    isActive: activeSection == section
                                ) {
                                    scrollToSection(section, proxy: proxy)
                                }
                            }
                        }
                        .frame(width: SettingsLayoutMetrics.sidebarWidth, alignment: .topLeading)
                        .accessibilityIdentifier("setupWindow.sidebar")

                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                trackedSection(.general) {
                                    generalSectionContent
                                }

                                trackedSection(.shortcuts) {
                                    shortcutsSectionContent
                                }

                                trackedSection(.assistant) {
                                    assistantSectionContent
                                }

                                trackedSection(.replacements) {
                                    replacementsSectionContent
                                }

                                trackedSection(.notes) {
                                    notesSectionContent
                                }

                                trackedSection(.history) {
                                    historySectionContent
                                }

                                trackedSection(.permissions) {
                                    permissionsSectionContent
                                }

                                trackedSection(.advanced) {
                                    advancedSectionContent
                                }
                            }
                            .padding(.trailing, 4)
                            .onPreferenceChange(SectionOffsetPreferenceKey.self) { offsets in
                                updateActiveSection(using: offsets)
                            }
                        }
                        .coordinateSpace(name: "settingsScroll")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .postEventGuideRequested)) { _ in
                        scrollToSection(.permissions, proxy: proxy)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(spacing: 12) {
                Button("Quit App") {
                    NSApp.terminate(nil)
                }
                .foregroundStyle(.red)

                Spacer()

                Button("Close") {
                    dismissWindow()
                }
                .accessibilityIdentifier("setupWindow.primaryAction")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(SetupColorPalette.appBackground)
        }
        .confirmationDialog(
            "Clear your word replacements?",
            isPresented: $isShowingClearAllReplacementsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Mine", role: .destructive) {
                clearAllWordReplacements()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the replacements you added yourself. Vocabulary packs stay on.")
        }
        .confirmationDialog(
            "Clear all saved history?",
            isPresented: $isShowingClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                historyVM.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes every saved transcription in the current history folder.")
        }
        .sheet(isPresented: $isShowingAssistantSystemPromptEditor) {
            AssistantSystemPromptSheet(
                prompt: rewriteSystemPromptBinding,
                onLoadFromFile: loadAssistantSystemPromptFromFile,
                onDismiss: { isShowingAssistantSystemPromptEditor = false }
            )
        }
    }
}
