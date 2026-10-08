// Checks the String Catalog against the app (#191): every key the compiler extracts
// is in the catalog, and every key in the catalog has a German translation.
// Usage: swift Tools/check-localizations.swift [DerivedData]   (from the repository root)
//
// Reads the keys from the .stringsdata files a build of the app leaves in its
// DerivedData (SWIFT_EMIT_LOC_STRINGS), by default build/DerivedData. That format is
// internal to Xcode: if a new Xcode changes it, the check fails rather than passes.

import Foundation

let catalogPath = "MacVocTrainNg/Resources/Localizable.xcstrings"
let catalogTable = "Localizable"
let language = "de"

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count <= 1 else {
    FileHandle.standardError.write(Data("usage: swift Tools/check-localizations.swift [DerivedData]\n".utf8))
    exit(2)
}
let derivedData = URL(fileURLWithPath: arguments.first ?? "build/DerivedData")
let repository = FileManager.default.currentDirectoryPath + "/"

var problems: [String] = []

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("✗ \(message)\n".utf8))
    exit(1)
}

func json(at url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { fail("\(url.path) is not a JSON object.") }
    return object
}

// MARK: Keys the compiler extracted

/// A key as the compiler found it in the source.
struct ExtractedKey {
    var table: String
    var key: String
    var place: String
}

/// The .stringsdata files of the app target, from every configuration and architecture built.
func stringsDataFiles() -> [URL] {
    let projectBuild = derivedData.appendingPathComponent("Build/Intermediates.noindex/MacVocTrainNg.build")
    guard let files = FileManager.default.enumerator(at: projectBuild, includingPropertiesForKeys: nil) else {
        return []
    }
    return files.compactMap { $0 as? URL }.filter {
        $0.pathExtension == "stringsdata" && $0.path.contains("/MacVocTrainNg.build/Objects-normal/")
    }
}

func extractedKeys(in url: URL) -> [ExtractedKey] {
    let file = json(at: url)
    guard file["version"] as? Int == 1, let source = file["source"] as? String,
        let tables = file["tables"] as? [String: [[String: Any]]]
    else { fail("\(url.path) has an unknown format; adapt this check to the new Xcode.") }
    let path = source.hasPrefix(repository) ? String(source.dropFirst(repository.count)) : source
    return tables.flatMap { table, entries in
        entries.map { entry in
            guard let key = entry["key"] as? String else {
                fail("\(url.path) has an entry without a key; adapt this check to the new Xcode.")
            }
            let line = (entry["location"] as? [String: Any])?["startingLine"] as? Int
            return ExtractedKey(table: table, key: key, place: line.map { "\(path):\($0)" } ?? path)
        }
    }
}

let files = stringsDataFiles()
if files.isEmpty {
    fail("No .stringsdata files below \(derivedData.path). Build the app with this -derivedDataPath first.")
}
let extracted = files.flatMap(extractedKeys)

// MARK: The catalog

let catalog = json(at: URL(fileURLWithPath: catalogPath))
guard let entries = catalog["strings"] as? [String: [String: Any]] else {
    fail("\(catalogPath) has no strings.")
}

var reported = Set<String>()
for key in extracted.sorted(by: { $0.place < $1.place }) where reported.insert(key.table + "\u{0}" + key.key).inserted {
    if key.table != catalogTable {
        problems.append("\(key.place): “\(key.key)” is in table \(key.table), which has no String Catalog.")
    } else if entries[key.key] == nil {
        problems.append("\(key.place): “\(key.key)” is missing from \(catalogPath).")
    }
}

/// The states of all string units below a localization: plural and device variations
/// and substitutions each carry their own.
func states(in node: Any) -> [String] {
    guard let object = node as? [String: Any] else { return [] }
    var result: [String] = []
    if let unit = object["stringUnit"] as? [String: Any] {
        result.append(unit["state"] as? String ?? "none")
    }
    for (name, value) in object where name != "stringUnit" {
        result += states(in: value)
    }
    return result
}

for (key, entry) in entries.sorted(by: { $0.key < $1.key }) where entry["shouldTranslate"] as? Bool != false {
    let localization = (entry["localizations"] as? [String: Any])?[language]
    let found = localization.map { states(in: $0) } ?? []
    if found.isEmpty {
        problems.append("\(catalogPath): “\(key)” has no translation into \(language).")
    } else if found.contains(where: { $0 != "translated" }) {
        problems.append("\(catalogPath): “\(key)” has a translation into \(language) that is not in state translated.")
    }
}

if !problems.isEmpty {
    for problem in problems {
        print("✗ \(problem)")
    }
    exit(1)
}
print("✓ \(Set(extracted.map(\.key)).count) keys in \(files.count) files, all in the catalog; \(entries.count) catalog entries, all translated.")
