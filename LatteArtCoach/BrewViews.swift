import LatteCore
import PhotosUI
import SwiftData
import SwiftUI

/// "Log this drink" on a result: brew and taste in a few lines, tap to edit.
struct DrinkLogCard: View {
  @Bindable var pour: Pour
  @State private var editing = false

  var body: some View {
    Button { editing = true } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Your drink").font(.display(.title3))
          Spacer()
          Text(lines.isEmpty ? "Log it" : "Edit").font(.subheadline.weight(.semibold)).foregroundStyle(Color.crema)
        }
        if lines.isEmpty {
          Text("Log the beans, shot and how it tasted. It turns into grinder advice and shows what you like.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          ForEach(lines, id: \.self) { line in
            Text(line).font(.subheadline).foregroundStyle(Color.espresso)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("drink-card")
    .sheet(isPresented: $editing) { DrinkLogEditor(pour: pour) }
  }

  private var lines: [String] {
    let brew = pour.brew
    var lines: [String] = []
    if let name = brew.beanName {
      var beans = name
      if let roaster = brew.roaster { beans += " · \(roaster)" }
      if let days = brew.daysOffRoast(on: pour.date) { beans += " · \(days) day\(days == 1 ? "" : "s") off roast" }
      lines.append(beans)
    }
    if let shot = brew.shotSummary { lines.append(shot) }
    if let milk = brew.milk { lines.append("\(milk.displayName) milk") }
    let taste = pour.taste
    let tasteParts = [taste.balance?.displayName, taste.rating.map { String(repeating: "★", count: $0) },
                      taste.notes.isEmpty ? nil : taste.notes.joined(separator: ", ")].compactMap { $0 }
    if !tasteParts.isEmpty { lines.append("Tasted: " + tasteParts.joined(separator: " · ")) }
    return lines
  }
}

/// One sheet for the whole drink: how it tasted, the shot, beans and milk.
struct DrinkLogEditor: View {
  @Bindable var pour: Pour
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Query(sort: \Bean.addedAt, order: .reverse) private var beans: [Bean]
  @State private var addingBean = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TasteFields(pour: pour)
        } header: {
          Text("How it tasted")
        }
        Section {
          number("Dose", value: $pour.doseGrams, unit: "g")
          number("Yield", value: $pour.yieldGrams, unit: "g")
          number("Shot time", value: $pour.shotSeconds, unit: "s")
          LabeledContent("Grind setting") {
            TextField("e.g. 12", text: Binding(get: { pour.grindSetting ?? "" }, set: { pour.grindSetting = $0.isEmpty ? nil : $0 }))
              .multilineTextAlignment(.trailing)
          }
        } header: {
          Text("Espresso")
        } footer: {
          Text("New pours start from your last pour's details, so you only change what changed.")
        }
        Section("Beans") {
          Picker("Beans", selection: $pour.bean) {
            Text("None").tag(Bean?.none)
            ForEach(beans) { bean in
              Text(bean.roaster.map { "\(bean.name) · \($0)" } ?? bean.name).tag(Bean?.some(bean))
            }
          }
          Button("Add new beans…") { addingBean = true }
        }
        Section("Milk") {
          Picker("Milk", selection: Binding(get: { pour.milk }, set: { pour.milk = $0 })) {
            Text("Not logged").tag(BrewDetails.Milk?.none)
            ForEach(BrewDetails.Milk.allCases) { Text($0.displayName).tag(BrewDetails.Milk?.some($0)) }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color.milk)
      .navigationTitle("Your drink")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") {
            try? context.save()
            dismiss()
          }
        }
      }
      .sheet(isPresented: $addingBean) {
        NewBeanForm { bean in
          context.insert(bean)
          pour.bean = bean
          try? context.save()
        }
      }
    }
    .tint(.crema)
  }

  private func number(_ label: String, value: Binding<Double?>, unit: String) -> some View {
    LabeledContent(label) {
      HStack(spacing: 4) {
        TextField("–", value: value, format: .number.precision(.fractionLength(0...1)))
          .keyboardType(.decimalPad)
          .multilineTextAlignment(.trailing)
        Text(unit).foregroundStyle(.secondary)
      }
    }
  }
}

/// A bag of beans: scan the label to fill it in, then check and fix. Also
/// edits a saved bag.
struct NewBeanForm: View {
  /// The saved bag being edited; nil for a new one.
  var editing: Bean?
  let onSave: (Bean) -> Void

  init(editing: Bean? = nil, onSave: @escaping (Bean) -> Void) {
    self.editing = editing
    self.onSave = onSave
  }
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var roaster = ""
  @State private var knowsRoastDate = false
  @State private var roastDate = Date.now
  @State private var origin = ""
  @State private var process = ""
  @State private var variety = ""
  @State private var altitude = ""
  @State private var roastLevel: BeanLabel.RoastLevel?
  @State private var roastLevelIsGuess = false
  @State private var notes = ""
  @State private var labelText: String?
  @State private var myNotes = ""
  @State private var loaded = false
  // Scanning
  @State private var pickerItem: PhotosPickerItem?
  @State private var showingCamera = false
  @State private var scanning = false
  @State private var scanNote: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if scanning {
            HStack(spacing: 10) {
              ProgressView()
              Text("Reading the bag…").foregroundStyle(.secondary)
            }
          } else {
            if CameraPicker.isAvailable {
              Button { showingCamera = true } label: { Label("Scan the bag", systemImage: "camera.viewfinder") }
                .accessibilityIdentifier("scan-bag")
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
              Label("Choose a photo of the bag", systemImage: "photo.on.rectangle")
            }
          }
        } footer: {
          Text(scanNote ?? "Photograph the label and the details fill in. Read on this iPhone; nothing is uploaded.")
        }
        Section("Coffee") {
          TextField("Name, e.g. Guji Hambela", text: $name)
          TextField("Roaster", text: $roaster)
        }
        Section {
          Toggle("Roast date on the bag", isOn: $knowsRoastDate)
          if knowsRoastDate {
            DatePicker("Roasted", selection: $roastDate, in: ...Date.now, displayedComponents: .date)
          }
          Picker("Roast level", selection: Binding(get: { roastLevel }, set: { roastLevel = $0; roastLevelIsGuess = false })) {
            Text("Not sure").tag(BeanLabel.RoastLevel?.none)
            ForEach(BeanLabel.RoastLevel.allCases) { Text($0.displayName).tag(BeanLabel.RoastLevel?.some($0)) }
          }
        } header: {
          Text("Roast")
        } footer: {
          Text(roastLevelIsGuess
            ? "Roast level guessed from the bag; change it if you know otherwise."
            : "Freshness changes the crema, and the crema changes how your art turns out.")
        }
        Section("From the bag") {
          TextField("Origin", text: $origin)
          TextField("Process, e.g. washed", text: $process)
          TextField("Variety", text: $variety)
          TextField("Altitude", text: $altitude)
          TextField("Tasting notes, comma separated", text: $notes, axis: .vertical)
        }
        Section("Your notes") {
          TextField("Anything to remember about this bag", text: $myNotes, axis: .vertical)
        }
        if let labelText, !labelText.isEmpty {
          Section {
            DisclosureGroup("Text read from the bag") {
              Text(labelText).font(.footnote.monospaced()).textSelection(.enabled)
              Button { UIPasteboard.general.string = labelText } label: { Label("Copy", systemImage: "doc.on.doc") }
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color.milk)
      .navigationTitle(editing == nil ? "New beans" : "Edit beans")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .onChange(of: pickerItem) { _, item in
        guard let item else { return }
        pickerItem = nil
        Task { if let data = try? await item.loadTransferable(type: Data.self) { await scan(data) } }
      }
      .fullScreenCover(isPresented: $showingCamera) {
        CameraPicker { data in
          showingCamera = false
          if let data { Task { await scan(data) } }
        }
        .ignoresSafeArea()
      }
      .onAppear(perform: load)
    }
    .tint(.crema)
  }

  private func load() {
    guard !loaded, let bean = editing else { return }
    loaded = true
    name = bean.name
    roaster = bean.roaster ?? ""
    knowsRoastDate = bean.roastDate != nil
    roastDate = bean.roastDate ?? .now
    origin = bean.origin ?? ""
    process = bean.process ?? ""
    variety = bean.variety ?? ""
    altitude = bean.altitude ?? ""
    roastLevel = bean.roastLevel
    roastLevelIsGuess = bean.roastLevelIsGuess
    notes = bean.tastingNotes.joined(separator: ", ")
    labelText = bean.labelText
    myNotes = bean.notes ?? ""
  }

  private func scan(_ data: Data) async {
    scanning = true
    defer { scanning = false }
    guard let result = try? await BagScanner.scan(data), !result.text.isEmpty else {
      scanNote = "Couldn't read any text. Try a closer, sharper photo of the label."
      return
    }
    let label = result.label
    // Only fill what was found; keep anything already typed.
    func fill(_ field: inout String, _ value: String?) { if field.isEmpty, let value { field = value } }
    fill(&name, result.name)
    fill(&roaster, result.roaster)
    fill(&origin, label.origin)
    fill(&process, label.process)
    fill(&variety, label.variety)
    fill(&altitude, label.altitude)
    if notes.isEmpty, !label.tastingNotes.isEmpty { notes = label.tastingNotes.joined(separator: ", ") }
    if let date = label.roastDate { roastDate = date; knowsRoastDate = true }
    if roastLevel == nil, let level = label.roastLevel { roastLevel = level; roastLevelIsGuess = label.roastLevelIsGuess }
    labelText = result.text
    let found = [label.roastDate == nil ? nil : "roast date", label.origin, label.process, label.tastingNotes.isEmpty ? nil : "tasting notes"]
      .compactMap { $0 }
    scanNote = found.isEmpty
      ? "Read the bag but found few details. Check and fill in the rest."
      : "Filled in from the bag. Check everything before saving."
  }

  private func save() {
    func clean(_ s: String) -> String? {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      return t.isEmpty ? nil : t
    }
    let bean = editing ?? Bean(name: "Beans")
    bean.name = clean(name) ?? "Beans"
    bean.roaster = clean(roaster)
    bean.roastDate = knowsRoastDate ? roastDate : nil
    bean.notes = clean(myNotes)
    bean.origin = clean(origin)
    bean.process = clean(process)
    bean.variety = clean(variety)
    bean.altitude = clean(altitude)
    bean.roastLevel = roastLevel
    bean.roastLevelIsGuess = roastLevelIsGuess
    bean.tastingNotes = notes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    bean.labelText = labelText
    onSave(bean)
    dismiss()
  }
}
