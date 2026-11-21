// Rename files from Recent Files: one file, or many at once with a prefix, suffix, find and replace, numbers and letter case.
import SwiftUI

struct RecentRenameSheet: View {
    var files: [RecentFile]
    var onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var fullName = ""
    @State private var prefix = ""
    @State private var suffix = ""
    @State private var find = ""
    @State private var replace = ""
    @State private var numbering = false
    @State private var start = 1
    @State private var letterCase = 0

    private var single: Bool { files.count == 1 }

    private func stem(_ file: RecentFile) -> String { ((file.location as NSString).lastPathComponent as NSString).deletingPathExtension }
    private func ext(_ file: RecentFile) -> String { (file.location as NSString).pathExtension }

    private func newStem(_ file: RecentFile, _ index: Int) -> String {
        var name = single && !fullName.trimmingCharacters(in: .whitespaces).isEmpty ? fullName.trimmingCharacters(in: .whitespaces) : stem(file)
        if !find.isEmpty { name = name.replacingOccurrences(of: find, with: replace) }
        switch letterCase {
        case 1: name = name.lowercased()
        case 2: name = name.capitalized
        case 3: name = name.uppercased()
        default: break
        }
        name = prefix + name + suffix
        if numbering { name += String(format: "_%02d", start + index) }
        return name
    }

    private func newFileName(_ file: RecentFile, _ index: Int) -> String {
        let base = newStem(file, index).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let e = ext(file)
        return e.isEmpty ? base : base + "." + e
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(single ? "Rename file" : "Rename \(files.count) files").font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.bordered)
            }
            if single { TextField("New name (leave empty to keep it)", text: $fullName).textFieldStyle(.roundedBorder) }
            HStack {
                TextField("Add at the start", text: $prefix).textFieldStyle(.roundedBorder)
                TextField("Add at the end", text: $suffix).textFieldStyle(.roundedBorder)
            }
            HStack {
                TextField("Find", text: $find).textFieldStyle(.roundedBorder)
                TextField("Replace with", text: $replace).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                Picker("Letters", selection: $letterCase) {
                    Text("As they are").tag(0); Text("all small").tag(1); Text("Each Word Big").tag(2); Text("ALL BIG").tag(3)
                }.frame(width: 260)
                Toggle("Number them", isOn: $numbering)
                if numbering { Stepper("from \(start)", value: $start, in: 0...9999) }
            }
            Text("Preview").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                        HStack(spacing: 6) {
                            Text((file.location as NSString).lastPathComponent).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Image(systemName: "arrow.right").font(.caption)
                            Text(newFileName(file, index)).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                        }.font(.callout)
                    }
                }
            }
            .frame(height: 150)
            HStack {
                Text("The files are renamed on this Mac.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Rename") { apply() }.buttonStyle(.borderedProminent).tint(Butter.coral)
            }
        }
        .padding(22).frame(width: 560)
    }

    private func apply() {
        var done = 0, failed = 0
        for (index, file) in files.enumerated() {
            let source = URL(fileURLWithPath: file.location)
            let target = source.deletingLastPathComponent().appendingPathComponent(newFileName(file, index))
            if target.path == source.path { continue }
            if FileManager.default.fileExists(atPath: target.path) { failed += 1; continue }
            do {
                try FileManager.default.moveItem(at: source, to: target)
                RecentFileStore.shared.didRename(file.id, to: target.path)
                done += 1
            } catch { failed += 1 }
        }
        onDone("Renamed \(done) file\(done == 1 ? "" : "s")." + (failed > 0 ? " \(failed) could not be renamed (name already used or file missing)." : ""))
        dismiss()
    }
}
