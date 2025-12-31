import SwiftUI

/// Sheet for importing QMK keyboard layouts from URL or file
struct QMKImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedLayoutId: String
    var onImportComplete: (() -> Void)? = nil
    
    @State private var importMethod: ImportMethod = .url
    @State private var urlString: String = ""
    @State private var selectedFileURL: URL?
    @State private var selectedVariant: String?
    @State private var layoutName: String = ""
    @State private var keyMappingType: KeyMappingType = .ansi
    
    @State private var availableVariants: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var warningMessage: String?
    @State private var showFilePicker = false
    @State private var fetchedJSONData: Data? // Cache fetched JSON to avoid double fetch
    
    enum ImportMethod {
        case url
        case file
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Import QMK Layout")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("qmk-import-cancel-button")
            }
            .padding(.horizontal)
            .padding(.top)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Import method selection
                    Picker("Import Method", selection: $importMethod) {
                        Text("From URL").tag(ImportMethod.url)
                        Text("From File").tag(ImportMethod.file)
                    }
                    .pickerStyle(.segmented)
                    
                    // URL input
                    if importMethod == .url {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QMK info.json URL")
                                .font(.headline)
                            TextField("https://raw.githubusercontent.com/qmk/qmk_firmware/.../info.json", text: $urlString)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("qmk-import-url-field")
                                .onChange(of: urlString) { _, newValue in
                                    // Validate URL format and warn if not GitHub
                                    if !newValue.isEmpty, let url = URL(string: newValue) {
                                        if url.scheme == "https" || url.scheme == "http" {
                                            if !url.absoluteString.contains("raw.githubusercontent.com") {
                                                warningMessage = "Warning: URL doesn't appear to be a GitHub raw URL. Import may fail if the URL doesn't point to valid QMK JSON."
                                            } else {
                                                warningMessage = nil
                                            }
                                        } else {
                                            warningMessage = "URL must use http or https protocol"
                                        }
                                    } else if !newValue.isEmpty {
                                        warningMessage = "Invalid URL format"
                                    } else {
                                        warningMessage = nil
                                    }
                                }
                            Text("Paste a GitHub raw URL to a QMK keyboard's info.json file")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // File picker
                    if importMethod == .file {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("QMK info.json File")
                                .font(.headline)
                            if let fileURL = selectedFileURL {
                                HStack {
                                    Text(fileURL.lastPathComponent)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Change") {
                                        showFilePicker = true
                                    }
                                }
                                .padding()
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            } else {
                                Button("Choose File") {
                                    showFilePicker = true
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("qmk-import-file-button")
                            }
                            Text("Select a QMK keyboard's info.json file from your computer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Key mapping type
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keyboard Type")
                            .font(.headline)
                        Picker("Keyboard Type", selection: $keyMappingType) {
                            Text("ANSI (US Standard)").tag(KeyMappingType.ansi)
                            Text("ISO (International)").tag(KeyMappingType.iso)
                        }
                        .pickerStyle(.segmented)
                        Text("Select ANSI for US keyboards, ISO for European/International keyboards")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Layout variant selection (shown after loading)
                    if !availableVariants.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Layout Variant")
                                .font(.headline)
                            Picker("Layout Variant", selection: $selectedVariant) {
                                Text("Default").tag(nil as String?)
                                ForEach(availableVariants, id: \.self) { variant in
                                    Text(variant.capitalized).tag(variant as String?)
                                }
                            }
                            .pickerStyle(.menu)
                            Text("Some keyboards have multiple layout variants (ANSI, ISO, etc.)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Layout name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Layout Name")
                            .font(.headline)
                        TextField("My Custom Keyboard", text: $layoutName)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("qmk-import-name-field")
                        Text("Give this layout a name for easy identification")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Warning message (non-fatal)
                    if let warning = warningMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(warning)
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Error message
                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Import button
                    Button {
                        Task {
                            await importLayout()
                        }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isLoading ? "Importing..." : "Import Layout")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || !canImport)
                    .accessibilityIdentifier("qmk-import-button")
                }
                .padding()
            }
        }
        .frame(width: 500, height: 600)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedFileURL = urls.first
                // Auto-load variants if file is selected
                if let fileURL = urls.first {
                    Task {
                        await loadVariants(from: fileURL)
                    }
                }
            case .failure(let error):
                errorMessage = "Failed to select file: \(error.localizedDescription)"
            }
        }
    }
    
    private var canImport: Bool {
        if importMethod == .url {
            return !urlString.isEmpty && URL(string: urlString) != nil && !layoutName.isEmpty
        } else {
            return selectedFileURL != nil && !layoutName.isEmpty
        }
    }
    
    private func loadVariants(from fileURL: URL) async {
        do {
            let data = try Data(contentsOf: fileURL)
            fetchedJSONData = data // Cache the data
            availableVariants = try QMKImportService.shared.getAvailableVariants(from: data)
            if !availableVariants.isEmpty && selectedVariant == nil {
                selectedVariant = availableVariants.first
            }
        } catch {
            errorMessage = "Failed to load layout variants: \(error.localizedDescription)"
        }
    }
    
    private func importLayout() async {
        isLoading = true
        errorMessage = nil
        warningMessage = nil
        
        do {
            let layout: PhysicalLayout
            let jsonData: Data
            
            if importMethod == .url {
                guard let url = URL(string: urlString) else {
                    throw QMKImportError.invalidURL("Invalid URL format")
                }
                
                // Fetch JSON if not already cached
                if let cached = fetchedJSONData {
                    jsonData = cached
                } else {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        throw QMKImportError.networkError("Failed to fetch JSON")
                    }
                    
                    jsonData = data
                    fetchedJSONData = data // Cache for later use
                }
                
                // Load variants if not already loaded
                if availableVariants.isEmpty {
                    availableVariants = try QMKImportService.shared.getAvailableVariants(from: jsonData)
                    if !availableVariants.isEmpty && selectedVariant == nil {
                        selectedVariant = availableVariants.first
                    }
                    isLoading = false
                    return // User needs to select variant
                }
                
                // Use cached data to avoid second fetch
                layout = try await QMKImportService.shared.importFromURL(
                    url,
                    layoutVariant: selectedVariant,
                    keyMappingType: keyMappingType
                )
            } else {
                guard let fileURL = selectedFileURL else {
                    throw QMKImportError.invalidURL("No file selected")
                }
                
                // Load file if not already cached
                if let cached = fetchedJSONData {
                    jsonData = cached
                } else {
                    jsonData = try Data(contentsOf: fileURL)
                    fetchedJSONData = jsonData // Cache for later use
                }
                
                // Load variants if not already loaded
                if availableVariants.isEmpty {
                    availableVariants = try QMKImportService.shared.getAvailableVariants(from: jsonData)
                    if !availableVariants.isEmpty && selectedVariant == nil {
                        selectedVariant = availableVariants.first
                    }
                    isLoading = false
                    return // User needs to select variant
                }
                
                layout = try await QMKImportService.shared.importFromFile(
                    fileURL,
                    layoutVariant: selectedVariant,
                    keyMappingType: keyMappingType
                )
            }
            
            // Save the layout
            await QMKImportService.shared.saveCustomLayout(
                layout: layout,
                name: layoutName,
                sourceURL: importMethod == .url ? urlString : nil,
                layoutJSON: jsonData,
                layoutVariant: selectedVariant
            )
            
            // Select the imported layout
            selectedLayoutId = layout.id
            
            // Notify completion handler
            onImportComplete?()
            
            // Dismiss sheet
            dismiss()
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

#Preview {
    QMKImportSheet(selectedLayoutId: .constant("macbook-us"))
}
