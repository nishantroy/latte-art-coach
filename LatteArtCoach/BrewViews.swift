import LatteCore
import PhotosUI
import SwiftData
import SwiftUI

/// "Brew details" on a result: a summary, tap to edit.
struct BrewCard: View {
  @Bindable var pour: Pour
  @State private var editing = false

  var body: some View {
    Button { editing = true } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Brew details").font(.display(.title3))
          Spacer()
          Text(pour.brew.isEmpty ? "Add" : "Edit").font(.subheadline.weight(.semibold)).foregroundStyle(Color.crema)
        }
        if pour.brew.isEmpty {
          Text("Log the beans, shot and milk to see how they affect your pours.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        } else {
          ForEach(lines, id: \.self) { line in
            Text(line).font(.subheadline).foregroundStyle(Color.espresso)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("brew-card")
    .sheet(isPresented: $editing) { BrewEditor(pour: pour) }
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
    return lines
  }
}

/// Edits one pour's beans, shot and milk.
struct BrewEditor: View {
  @Bindable var pour: Pour
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @Query(sort: \Bean.addedAt, order: .reverse) private var beans: [Bean]
  @State private var addingBean = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Beans") {
          Picker("Beans", selection: $pour.bean) {
            Text("None").tag(Bean?.none)
            ForEach(beans) { bean in
              Text(bean.roaster.map { "\(bean.name) · \($0)" } ?? bean.name).tag(Bean?.some(bean))
            }
          }
          Button("Add new beans…") { addingBean = true }
        }
        Section {
          number("Dose", value: $pour.doseGrams, unit: "g")
          number("Yield", value: $pour.yieldGrams, unit: "g")
          number("Shot time", value: $pour.shotSeconds, unit: "s")
          LabeledContent("Grind setting") {
            TextField("e.g. 12", text: Binding(get: { pour.grindSetting ?? "" }, set: { pour.grindSetting = $0.isEmpty ? nil : $0 }))
              .multilineTextAlignment(.trailing)
          }
          if let summary = pour.brew.shotSummary {
            Text(summary).font(.footnote).foregroundStyle(.secondary)
          }
        } header: {
          Text("Espresso")
        } footer: {
          Text("New pours start from your last pour's details, so you only change what changed.")
        }
        Section("Milk") {
          Picker("Milk", selection: Binding(get: { pour.milk }, set: { pour.milk = $0 })) {
            Text("Not logged").tag(BrewDetails.Milk?.none)
            ForEach(BrewDetails.Milk.allCases) { Text($0.displayName).tag(BrewDetails.Milk?.some($0)) }
          }
        }
      }
      .navigationTitle("Brew details")
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

/// A new bag of beans: scan the label to fill it in, then check and fix.
struct NewBeanForm: View {
  let onSave: (Bean) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var roaster = ""
  @State private var knowsRoastDate = true
  @State private var roastDate = Date.now
  @State private var origin = ""
  @State private var process = ""
  @State private var variety = ""
  @State private var altitude = ""
  @State private var roastLevel: BeanLabel.RoastLevel?
  @State private var roastLevelIsGuess = false
  @State private var notes = ""
  @State private var labelText: String?
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
            ? "Roast level guessed from the tasting notes; change it if the bag says otherwise."
            : "Freshness changes the crema, and the crema changes how your art turns out.")
        }
        Section("From the bag") {
          TextField("Origin", text: $origin)
          TextField("Process, e.g. washed", text: $process)
          TextField("Variety", text: $variety)
          TextField("Altitude", text: $altitude)
          TextField("Tasting notes, comma separated", text: $notes, axis: .vertical)
        }
      }
      .navigationTitle("New beans")
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
    }
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
    let bean = Bean(name: clean(name) ?? "Beans", roaster: clean(roaster), roastDate: knowsRoastDate ? roastDate : nil)
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
