import SwiftUI
import UniformTypeIdentifiers
import FoundationModels

struct MeridianView: View {
    @StateObject private var viewModel = MeridianViewModel()
    @State private var selectedExperience: Experience?
    @State private var showingNewExperience = false
    @State private var experiencePendingDeletion: Experience?
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedExperience: $selectedExperience,
                showingNewExperience: $showingNewExperience,
                experiences: viewModel.experiences,
                onDeleteExperience: { experience in
                    experiencePendingDeletion = experience
                }
            )
        } detail: {
            if showingNewExperience {
                NewExperienceView(viewModel: viewModel, selection: $selectedExperience)
            } else if let experience = selectedExperience {
                ExperienceDetailView(
                    experience: experience,
                    onRenameSpeaker: { speakerID, newName in
                        viewModel.updateSpeakerName(
                            for: experience.id,
                            speakerID: speakerID,
                            newName: newName
                        )
                    }
                )
            } else {
                EmptyStateView()
            }
        }
        .toolbar {
            if !showingNewExperience, let experience = selectedExperience {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        experiencePendingDeletion = experience
                    } label: {
                        Label("Delete Experience", systemImage: "trash")
                    }
                    #if os(macOS)
                    .help("Delete the selected experience")
                    #endif
                }
            }
        }
        .alert(item: $experiencePendingDeletion) { experience in
            Alert(
                title: Text("Delete Experience?"),
                message: Text("This will remove \"\(experience.title)\" from Meridian."),
                primaryButton: .destructive(Text("Delete")) {
                    handleDelete(experience)
                    experiencePendingDeletion = nil
                },
                secondaryButton: .cancel {
                    experiencePendingDeletion = nil
                }
            )
        }
        .onChange(of: viewModel.experiences) { _, newExperiences in
            guard !newExperiences.isEmpty else {
                selectedExperience = nil
                return
            }
            
            let currentSelectionID = selectedExperience?.id
            let updatedSelection = currentSelectionID.flatMap { id in
                newExperiences.first(where: { $0.id == id })
            } ?? newExperiences.first
            
            selectedExperience = updatedSelection
            showingNewExperience = false
        }
    }
    
    private func handleDelete(_ experience: Experience) {
        let didDelete = viewModel.deleteExperience(experience)
        guard didDelete else { return }
        
        if viewModel.experiences.isEmpty {
            selectedExperience = nil
        } else if selectedExperience?.id == experience.id {
            selectedExperience = viewModel.experiences.first
        }
        showingNewExperience = false
    }
}

// MARK: - Sidebar
struct SidebarView: View {
    @Binding var selectedExperience: Experience?
    @Binding var showingNewExperience: Bool
    let experiences: [Experience]
    let onDeleteExperience: (Experience) -> Void
    
    var body: some View {
        List(selection: $selectedExperience) {
            // New Experience Button
            Button(action: {
                selectedExperience = nil
                showingNewExperience = true
            }) {
                Label {
                    Text("New Experience")
                        .fontWeight(.medium)
                } icon: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.large)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            
            Divider()
                .padding(.vertical, 4)
            
            // Past Experiences
            Section("Recent") {
                ForEach(experiences) { experience in
                    ExperienceRow(
                        experience: experience,
                        isSelected: selectedExperience?.id == experience.id
                    )
                    .tag(experience)
                    .onTapGesture {
                        selectedExperience = experience
                        showingNewExperience = false
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            onDeleteExperience(experience)
                        } label: {
                            Label("Delete Experience", systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    guard let index = indexSet.first,
                          experiences.indices.contains(index) else {
                        return
                    }
                    onDeleteExperience(experiences[index])
                }
            }
        }
        .navigationTitle("Meridian")
        .listStyle(SidebarListStyle())
        #if os(macOS)
        .onDeleteCommand {
            if let selection = selectedExperience {
                onDeleteExperience(selection)
            }
        }
        #endif
    }
}

// MARK: - Experience Row
struct ExperienceRow: View {
    let experience: Experience
    let isSelected: Bool
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    var body: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .imageScale(.large)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(experience.title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(dateFormatter.string(from: experience.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let duration = experience.duration {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(duration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let speakers = experience.speakerCount {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Label("\(speakers)", systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - New Experience View
struct NewExperienceView: View {
    @ObservedObject var viewModel: MeridianViewModel
    @Binding var selection: Experience?
    @State private var dragOver = false
    @State private var showingFileImporter = false
    @State private var showingLinkSheet = false
    @State private var playlistLink = ""
    
    @State private var showStatusBanner = true
    
    private let allowedContentTypes: [UTType] = [.audio, .movie]
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                
                Text("Start New Experience")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Choose how you'd like to begin transcribing")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 20)
            
            // Options Grid
            HStack(spacing: 20) {
                // Upload File Option
                OptionCard(
                    icon: "doc.badge.arrow.up.fill",
                    title: "Upload File",
                    description: "Import audio or video files",
                    color: .blue,
                    action: {
                        showingFileImporter = true
                    }
                )
                
                // Playlist Link Option
                OptionCard(
                    icon: "link.circle.fill",
                    title: "Paste Playlist Link",
                    description: "YouTube or other platforms",
                    color: .purple,
                    action: {
                        playlistLink = ""
                        showingLinkSheet = true
                    }
                )
                
                // Start Recording Option
                OptionCard(
                    icon: "mic.circle.fill",
                    title: "Start Recording",
                    description: "Record live audio",
                    color: .red,
                    action: {
                        Task {
                            await viewModel.ensureWhisperServer()
                        }
                    }
                )
            }
            .padding(.horizontal)
            
            // Drag and Drop Area
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundColor(dragOver ? .accentColor : Color.secondary.opacity(0.3))
                .frame(height: 100)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Or drag and drop files here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                )
                .padding(.horizontal)
                .onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in
                    guard let provider = providers.first else {
                        return false
                    }
                    let identifier = UTType.fileURL.identifier
                    provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, error in
                        if let error {
                            Task { await MainActor.run { viewModel.reportClientError(message: error.localizedDescription) } }
                            return
                        }
                        let url: URL?
                        if let data = item as? Data {
                            url = URL(dataRepresentation: data, relativeTo: nil)
                        } else {
                            url = item as? URL
                        }
                        guard let resolvedURL = url else {
                            Task { await MainActor.run { viewModel.reportClientError(message: "Unable to read dropped file.") } }
                            return
                        }
                        Task {
                            await viewModel.upload(fileURL: resolvedURL)
                        }
                    }
                    return true
                }
            
            if showStatusBanner, let message = viewModel.status.message {
                StatusBannerView(status: viewModel.status, message: message, onClose: { showStatusBanner = false })
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await viewModel.upload(fileURL: url)
                }
            case .failure(let error):
                Task { await MainActor.run { viewModel.reportClientError(message: error.localizedDescription) } }
            }
        }
        .sheet(isPresented: $showingLinkSheet) {
            PlaylistLinkSheet(
                link: $playlistLink,
                onCancel: {
                    showingLinkSheet = false
                },
                onSubmit: { link in
                    showingLinkSheet = false
                    Task {
                        await viewModel.process(input: link)
                    }
                }
            )
        }
        .onChange(of: viewModel.status.message) { _, _ in
            showStatusBanner = true
        }
        .onChange(of: viewModel.experiences) { _, experiences in
            selection = experiences.first
        }
    }
}

// MARK: - Option Card
struct OptionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(color.opacity(0.1))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: icon)
                        .font(.system(size: 36))
                        .foregroundColor(color)
                }
                
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(width: 160, height: 200)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(isHovering ? 0.15 : 0.05), radius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.spring(response: 0.3), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct StatusBannerView: View {
    let status: MeridianViewModel.Status
    let message: String
    let onClose: () -> Void
    
    private var iconName: String {
        switch status {
        case .idle:
            return "circle"
        case .working:
            return "hourglass"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var accentColor: Color {
        switch status {
        case .idle:
            return .secondary
        case .working:
            return .accentColor
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundColor(accentColor)
            Text(message)
                .font(.callout)
                .foregroundColor(.primary)
                .lineLimit(3)
            Spacer()
            if status.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.5)
            }
            
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
}

struct PlaylistLinkSheet: View {
    @Binding var link: String
    let onCancel: () -> Void
    let onSubmit: (String) -> Void
    
    private var trimmedLink: String {
        link.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        NavigationStack  {
            Form {
                Section("Playlist Link") {
                    TextField("", text: $link)
                }
            }
            .frame(minWidth: 400, minHeight: 220)
            .navigationTitle("Process Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Process") {
                        onSubmit(trimmedLink)
                    }
                    .disabled(trimmedLink.isEmpty)
                }
            }
        }
    }
}

// MARK: - Experience Detail View
struct ExperienceDetailView: View {
    let experience: Experience
    let onRenameSpeaker: (String, String) -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerView
                metadataView
                TranscriptSection(
                    transcript: experience.transcript,
                    onRenameSpeaker: { speakerID, newName in
                        onRenameSpeaker(speakerID, newName)
                    }
                )
                if !experience.outputFile.isEmpty {
                    OutputFileSection(outputFile: experience.outputFile)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(experience.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Created \(experience.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var metadataView: some View {
        if experience.duration != nil || experience.speakerCount != nil {
            HStack(spacing: 12) {
                if let duration = experience.duration {
                    Label(duration, systemImage: "clock")
                }
                if let speakerCount = experience.speakerCount {
                    Label(
                        "\(speakerCount) speaker\(speakerCount == 1 ? "" : "s")",
                        systemImage: speakerCount == 1 ? "person.fill" : "person.2.fill"
                    )
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
}

private struct TranscriptSection: View {
    let transcript: CombinedTranscript
    let onRenameSpeaker: (String, String) -> Void
    
    @State private var editingSpeakerID: String?
    @State private var editingName: String = ""
    @FocusState private var focusedSpeakerID: String?
    
    private var speakerDisplayNames: [String: String] {
        var resolved: [String: String] = [:]
        if let speakers = transcript.speakers {
            for (identifier, speaker) in speakers {
                let candidates: [String?] = [
                    speaker.name,
                    speaker.label,
                    speaker.metadata?["label"],
                    speaker.metadata?["name"]
                ]
                if let match = candidates
                    .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                    .first(where: { !$0.isEmpty }) {
                    resolved[identifier] = match
                }
            }
        }
        
        var fallbackIndex = 1
        for segment in transcript.segments {
            guard let speakerID = segment.speaker else { continue }
            if resolved[speakerID] == nil {
                resolved[speakerID] = "Speaker \(fallbackIndex)"
                fallbackIndex += 1
            }
        }
        
        return resolved
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcript")
                .font(.title3)
                .fontWeight(.semibold)
            
            if transcript.segments.isEmpty {
                Text("Transcript is not available.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(transcript.segments) { segment in
                        TranscriptSegmentRow(
                            segment: segment,
                            speakerID: segment.speaker,
                            speakerName: speakerName(for: segment),
                            isEditing: editingSpeakerID == segment.speaker,
                            editingName: $editingName,
                            focusedSpeakerID: $focusedSpeakerID,
                            startEditing: {
                                if let speakerID = segment.speaker {
                                    startEditingSpeaker(speakerID: speakerID, currentName: speakerName(for: segment) ?? speakerID)
                                }
                            },
                            commitEditing: commitEditing,
                            cancelEditing: cancelEditing
                        )
                    }
                }
            }
        }
        .onChange(of: focusedSpeakerID) { newFocused in
            guard let editingSpeakerID else { return }
            if newFocused != editingSpeakerID {
                cancelEditing()
            }
        }
    }
    
    private func speakerName(for segment: CombinedTranscript.Segment) -> String? {
        guard let speakerID = segment.speaker else {
            return nil
        }
        return speakerDisplayNames[speakerID] ?? speakerID
    }
    
    private func startEditingSpeaker(speakerID: String, currentName: String) {
        editingSpeakerID = speakerID
        editingName = currentName.trimmingCharacters(in: .whitespacesAndNewlines)
        focusedSpeakerID = speakerID
    }
    
    private func commitEditing() {
        guard let speakerID = editingSpeakerID else { return }
        let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelEditing()
            return
        }
        onRenameSpeaker(speakerID, trimmed)
        editingSpeakerID = nil
        editingName = ""
        focusedSpeakerID = nil
    }
    
    private func cancelEditing() {
        editingSpeakerID = nil
        editingName = ""
        focusedSpeakerID = nil
    }
}

private struct TranscriptSegmentRow: View {
    let segment: CombinedTranscript.Segment
    let speakerID: String?
    let speakerName: String?
    let isEditing: Bool
    @Binding var editingName: String
    let focusedSpeakerID: FocusState<String?>.Binding
    let startEditing: () -> Void
    let commitEditing: () -> Void
    let cancelEditing: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                if let displayName = resolvedSpeakerName {
                    speakerHeader(displayName: displayName)
                }
                
                Spacer()
                
                if let timeSummary = timeSummary {
                    Text(timeSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(segment.text)
                .font(.body)
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
    
    @ViewBuilder
    private func speakerHeader(displayName: String) -> some View {
        if isEditing {
            HStack(spacing: 8) {
                TextField("Speaker name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .focused(focusedSpeakerID, equals: speakerID)
                    .onSubmit {
                        commitEditing()
                    }
                Button {
                    commitEditing()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.return, modifiers: [])
                
                Button(role: .cancel) {
                    cancelEditing()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
            }
            .font(.headline)
        } else {
            Text(displayName)
                .font(.headline)
                .onTapGesture {
                    startEditing()
                }
        }
    }
    
    private var timeSummary: String? {
        let startString = Self.formatTime(segment.start)
        let endString = Self.formatTime(segment.end)
        
        switch (startString, endString) {
        case let (start?, end?):
            return "\(start) – \(end)"
        case let (start?, nil):
            return start
        case let (nil, end?):
            return end
        default:
            return nil
        }
    }
    
    private static func formatTime(_ value: Double?) -> String? {
        guard let value else {
            return nil
        }
        
        let totalSeconds = Int(round(value))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private var resolvedSpeakerName: String? {
        if let speakerName {
            return speakerName
        }
        return speakerID
    }
}

private struct OutputFileSection: View {
    let outputFile: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output File")
                .font(.headline)
            Text(outputFile)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Select an experience or create a new one")
                .font(.title2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
    }
}


