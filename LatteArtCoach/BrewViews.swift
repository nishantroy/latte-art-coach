import LatteCore
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

/// Name, roaster and roast date for a new bag.
struct NewBeanForm: View {
  let onSave: (Bean) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var roaster = ""
  @State private var knowsRoastDate = true
  @State private var roastDate = Date.now

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name, e.g. Guji Natural", text: $name)
          TextField("Roaster", text: $roaster)
        }
        Section {
          Toggle("Roast date on the bag", isOn: $knowsRoastDate)
          if knowsRoastDate {
            DatePicker("Roasted", selection: $roastDate, in: ...Date.now, displayedComponents: .date)
          }
        } footer: {
          Text("Freshness changes the crema, and the crema changes how your art turns out.")
        }
      }
      .navigationTitle("New beans")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            let trimmed = roaster.trimmingCharacters(in: .whitespaces)
            onSave(Bean(name: name.trimmingCharacters(in: .whitespaces), roaster: trimmed.isEmpty ? nil : trimmed,
                        roastDate: knowsRoastDate ? roastDate : nil))
            dismiss()
          }
          .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
  }
}
