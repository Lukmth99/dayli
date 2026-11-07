import SwiftUI
import SwiftData
import PhotosUI
import DayliCore

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [UserProfile]
    @Query private var settingsList: [AppSettings]
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                if let profile = profiles.first {
                    Section {
                        HStack(spacing: DayliSpacing.md) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                AvatarView(initials: profile.initials, photoData: profile.photoData, size: 64)
                                    .overlay(alignment: .bottomTrailing) {
                                        Image(systemName: "camera.circle.fill").foregroundStyle(DayliColor.primary).background(Circle().fill(DayliColor.surface))
                                    }
                            }
                            .accessibilityLabel("Alterar foto de perfil")
                            VStack(alignment: .leading) {
                                TextField("Seu nome", text: Binding(
                                    get: { profile.name },
                                    set: { profile.name = String($0.prefix(60)) }))
                                    .font(DayliFont.headlineMedium)
                                    .onSubmit { env.repository.commit() }
                                Text("Sua vida, no seu ritmo.").font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary)
                            }
                        }
                        if profile.photoData != nil {
                            Button("Remover foto", role: .destructive) {
                                profile.photoData = nil
                                env.repository.commit()
                            }
                        }
                    }
                }

                if let settings = settingsList.first {
                    Section("Preferências") {
                        Picker("Aparência", selection: Binding(get: { settings.appearance }, set: { settings.appearance = $0; env.repository.commit() })) {
                            ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                        }
                        LabeledContent("Idioma", value: "Português (Brasil)")
                        NavigationLink("Rotina habitual") { RoutineSettingsView() }
                        NavigationLink("Áreas da vida") { LifeAreasSettingsView() }
                        NavigationLink("Categorias") { CategoriesSettingsView() }
                    }
                    Section("Lembretes e integrações") {
                        NavigationLink("Notificações") { NotificationSettingsView() }
                        NavigationLink("Calendário Apple") { CalendarIntegrationView() }
                    }
                    Section("Privacidade e IA") {
                        NavigationLink("Privacidade") { PrivacySettingsView() }
                        NavigationLink("Inteligência artificial") { AISettingsView() }
                    }
                    Section("Seus dados") {
                        NavigationLink("Exportar, demonstração e exclusão") { DataManagementView() }
                    }
                    Section {
                        NavigationLink("Sobre o Dayli") { AboutView() }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .dayliScreenBackground()
            .navigationTitle("Perfil")
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let resized = Self.resize(data) {
                        profiles.first?.photoData = resized
                        env.repository.commit()
                    }
                    photoItem = nil
                }
            }
        }
    }

    /// Reduz a foto (≤ 512 px, JPEG) para minimizar dados armazenados.
    static func resize(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 512
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.8) { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

// MARK: - Rotina

struct RoutineSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var routine = RoutineSettings.default
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Sono") {
                TimeOfDayPicker(title: "Acordar", value: $routine.wake)
                TimeOfDayPicker(title: "Dormir", value: $routine.sleep)
            }
            Section("Trabalho") {
                TimeOfDayPicker(title: "Início", value: $routine.workStart)
                TimeOfDayPicker(title: "Fim", value: $routine.workEnd)
                WeekdayPicker(selection: $routine.workdays).padding(.vertical, 4)
            }
            Section {
                Stepper("Respiro entre atividades: \(routine.bufferMinutes) min", value: $routine.bufferMinutes, in: 0...60, step: 5)
                Stepper("Limite de tarefas pessoais por dia: \(DayliFormat.duration(minutes: routine.maxPersonalFocusMinutes))",
                        value: $routine.maxPersonalFocusMinutes, in: 30...600, step: 30)
                Picker("Estudar de preferência", selection: $routine.studyPreference) {
                    ForEach(DayPeriodPreference.allCases) { Text($0.title).tag($0) }
                }
                Picker("Treinar de preferência", selection: $routine.workoutPreference) {
                    ForEach(DayPeriodPreference.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Planejamento")
            } footer: {
                Text("O limite diário evita que o planejamento automático encha seu tempo livre.")
            }
        }
        .scrollContentBackground(.hidden)
        .dayliScreenBackground()
        .navigationTitle("Rotina")
        .onAppear {
            guard !loaded else { return }
            loaded = true
            routine = env.repository.routine
        }
        .onChange(of: routine) { _, newValue in
            guard loaded else { return }
            env.repository.routinePreference().routine = newValue
            env.repository.commit()
        }
    }
}

struct LifeAreasSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var settingsList: [AppSettings]

    var body: some View {
        Form {
            if let settings = settingsList.first {
                Section {
                    ForEach(LifeArea.allCases) { area in
                        Toggle(isOn: Binding(
                            get: { settings.selectedAreas.contains(area) },
                            set: { on in
                                var areas = settings.selectedAreas
                                if on { areas.insert(area) } else { areas.remove(area) }
                                settings.selectedAreas = areas
                                env.repository.commit()
                            })) {
                            Label(area.title, systemImage: area.symbolName)
                        }
                    }
                } footer: {
                    Text("As áreas escolhidas aparecem em Minha Vida. Nenhum dado é apagado ao desativar uma área.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .dayliScreenBackground()
        .navigationTitle("Áreas da vida")
    }
}

// MARK: - Categorias

struct CategoriesSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Query(sort: \LifeCategory.sortOrder) private var categories: [LifeCategory]
    @State private var editing: LifeCategory?
    @State private var creating = false
    @State private var pendingDeletion: LifeCategory?

    var body: some View {
        List {
            ForEach(categories) { category in
                Button { editing = category } label: {
                    HStack {
                        Image(systemName: category.symbolName)
                            .foregroundStyle(DayliColor.ink(for: category.colorHex))
                            .frame(width: 32, height: 32)
                            .background(Color(hex: category.colorHex).opacity(0.2), in: Circle())
                        Text(category.name).foregroundStyle(DayliColor.textPrimary)
                        Spacer()
                        if category.isDefault { Text("Padrão").font(DayliFont.caption).foregroundStyle(DayliColor.textSecondary) }
                    }
                }
                .swipeActions {
                    Button("Excluir", role: .destructive) { pendingDeletion = category }
                }
            }
            .onMove { from, to in
                var ordered = categories
                ordered.move(fromOffsets: from, toOffset: to)
                for (index, c) in ordered.enumerated() { c.sortOrder = index }
                env.repository.commit()
            }
        }
        .scrollContentBackground(.hidden)
        .dayliScreenBackground()
        .navigationTitle("Categorias")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { creating = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nova categoria") }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $editing) { CategoryEditorView(category: $0) }
        .sheet(isPresented: $creating) { CategoryEditorView(category: nil) }
        .confirmationDialog("Excluir categoria?", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            titleVisibility: .visible, presenting: pendingDeletion) { category in
            Button("Excluir", role: .destructive) { env.repository.deleteCategory(category); pendingDeletion = nil }
        } message: { _ in
            Text("Tarefas, compromissos, hábitos e metas desta categoria não serão apagados — apenas ficarão sem categoria.")
        }
    }
}

struct CategoryEditorView: View {
    let category: LifeCategory?
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var colorHex = "#B8A3CE"
    @State private var symbol = "tag"
    @State private var loaded = false

    private let symbols = ["tag", "briefcase", "book.closed", "figure.run", "leaf", "heart", "house", "airplane", "cart", "music.note", "paintbrush", "pawprint"]

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome", text: $name)
                Section("Cor") { ColorPalettePicker(selection: $colorHex) }
                Section("Ícone") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6)) {
                        ForEach(symbols, id: \.self) { s in
                            Button { symbol = s } label: {
                                Image(systemName: s)
                                    .frame(width: 40, height: 40)
                                    .background(symbol == s ? Color(hex: colorHex).opacity(0.35) : DayliColor.surfaceMuted, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(s)
                        }
                    }
                }
                Section { CategoryChip(name: name.isEmpty ? "Prévia" : name, colorHex: colorHex, symbolName: symbol) }
            }
            .navigationTitle(category == nil ? "Nova categoria" : "Editar categoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        if let category, let clean = InputValidator.sanitizedTitle(name) {
                            category.name = String(clean.prefix(40))
                            category.colorHex = colorHex
                            category.symbolName = symbol
                            env.repository.commit()
                        } else {
                            env.repository.createCategory(name: name, colorHex: colorHex, symbolName: symbol)
                        }
                        dismiss()
                    }
                    .disabled(InputValidator.sanitizedTitle(name) == nil)
                }
            }
            .onAppear {
                guard !loaded, let category else { return }
                loaded = true
                name = category.name
                colorHex = category.colorHex
                symbol = category.symbolName
            }
        }
    }
}
