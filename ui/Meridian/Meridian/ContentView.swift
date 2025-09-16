import SwiftUI

// MARK: - Data Models
struct Experience: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let date: Date
    let duration: String?
    let speakerCount: Int?
    
    static let mockData: [Experience] = [
        Experience(title: "Team Meeting", date: Date().addingTimeInterval(-86400), duration: "45:23", speakerCount: 4),
        Experience(title: "Podcast Episode", date: Date().addingTimeInterval(-172800), duration: "1:23:45", speakerCount: 2),
        Experience(title: "Interview Recording", date: Date().addingTimeInterval(-259200), duration: "32:10", speakerCount: 2),
        Experience(title: "Lecture Notes", date: Date().addingTimeInterval(-345600), duration: "1:45:00", speakerCount: 1)
    ]
}

// MARK: - Main View
struct MeridianView: View {
    @State private var selectedExperience: Experience?
    @State private var showingNewExperience = false
    @State private var experiences = Experience.mockData
    
    var body: some View {
        NavigationSplitView {
            SidebarView(
                selectedExperience: $selectedExperience,
                showingNewExperience: $showingNewExperience,
                experiences: experiences
            )
        } detail: {
            if showingNewExperience {
                NewExperienceView()
            } else if let experience = selectedExperience {
                ExperienceDetailView(experience: experience)
            } else {
                EmptyStateView()
            }
        }
    }
}

// MARK: - Sidebar
struct SidebarView: View {
    @Binding var selectedExperience: Experience?
    @Binding var showingNewExperience: Bool
    let experiences: [Experience]
    
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
                }
            }
        }
        .navigationTitle("Meridian")
        .listStyle(SidebarListStyle())
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
    @State private var dragOver = false
    
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
                        // Handle file upload
                    }
                )
                
                // Playlist Link Option
                OptionCard(
                    icon: "link.circle.fill",
                    title: "Paste Playlist Link",
                    description: "YouTube or other platforms",
                    color: .purple,
                    action: {
                        // Handle playlist link
                    }
                )
                
                // Start Recording Option
                OptionCard(
                    icon: "mic.circle.fill",
                    title: "Start Recording",
                    description: "Record live audio",
                    color: .red,
                    action: {
                        // Handle recording
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
                    // Handle file drop
                    return true
                }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
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

// MARK: - Experience Detail View (Placeholder)
struct ExperienceDetailView: View {
    let experience: Experience
    
    var body: some View {
        VStack {
            Text(experience.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Experience details will be shown here")
                .foregroundColor(.secondary)
                .padding()
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
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


