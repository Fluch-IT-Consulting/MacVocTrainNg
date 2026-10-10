// Checks the String Catalog against the app (#191): every key the compiler extracts
// is in the catalog, and every key in the catalog has a German translation: in state
// translated, not empty, and with the plural forms German needs.
// Usage: swift Tools/check-localizations.swift [DerivedData]   (from the repository root)
//
// Reads the keys from the .stringsdata files a build of the app leaves in its
// DerivedData (SWIFT_EMIT_LOC_STRINGS), by default build/DerivedData. That format is
// internal to Xcode: if a new Xcode changes it, the check fails rather than passes.

import Foundation

let catalogPath = "Shared/Resources/Localizable.xcstrings"
let catalogTable = "Localizable"
let language = "de"
let pluralForms = ["one", "other"]

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count <= 1 else {
    FileHandle.standardError.write(Data("usage: swift Tools/check-localizations.swift [DerivedData]\n".utf8))
    exit(2)
}
let derivedData = URL(fileURLWithPath: arguments.first ?? "build/DerivedData")
let repository = FileManager.default.currentDirectoryPath + "/"

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

func failUnknownFormat(_ url: URL, _ problem: String) -> Never {
    fail("\(url.path) \(problem); adapt this check to the new Xcode.")
}

// MARK: Keys the compiler extracted

/// A key in a strings table.
struct TableKey: Hashable {
    var table: String
    var key: String
}

/// A key as the compiler found it in the source.
struct ExtractedKey {
    var tableKey: TableKey
    /// `path:line` in the repository.
    var location: String
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
    else { failUnknownFormat(url, "has an unknown format") }
    let path = source.hasPrefix(repository) ? String(source.dropFirst(repository.count)) : source
    return tables.flatMap { table, entries in
        entries.map { entry in
            guard let key = entry["key"] as? String else { failUnknownFormat(url, "has an entry without a key") }
            let line = (entry["location"] as? [String: Any])?["startingLine"] as? Int
            return ExtractedKey(tableKey: TableKey(table: table, key: key), location: line.map { "\(path):\($0)" } ?? path)
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
guard let catalogStrings = catalog["strings"] as? [String: [String: Any]] else {
    fail("\(catalogPath) has no strings.")
}

var problems: [String] = []

var reported = Set<TableKey>()
for extractedKey in extracted.sorted(by: { $0.location < $1.location }) where reported.insert(extractedKey.tableKey).inserted {
    let (table, key) = (extractedKey.tableKey.table, extractedKey.tableKey.key)
    if table != catalogTable {
        problems.append("\(extractedKey.location): “\(key)” is in table \(table), which has no String Catalog.")
    } else if catalogStrings[key] == nil {
        problems.append("\(extractedKey.location): “\(key)” is missing from \(catalogPath).")
    }
}

/// All string units below a localization: plural and device variations and
/// substitutions each carry their own.
func stringUnits(in node: Any) -> [[String: Any]] {
    guard let object = node as? [String: Any] else { return [] }
    var result: [[String: Any]] = []
    if let unit = object["stringUnit"] as? [String: Any] {
        result.append(unit)
    }
    for (name, value) in object where name != "stringUnit" {
        result += stringUnits(in: value)
    }
    return result
}

/// The forms of every plural variation below a localization, the key's own and its
/// substitutions'.
func pluralVariations(in node: Any) -> [[String]] {
    guard let object = node as? [String: Any] else { return [] }
    var result: [[String]] = []
    if let plural = (object["variations"] as? [String: Any])?["plural"] as? [String: Any] {
        result.append(Array(plural.keys))
    }
    for value in object.values {
        result += pluralVariations(in: value)
    }
    return result
}

let toTranslate = catalogStrings.filter { $0.value["shouldTranslate"] as? Bool != false }
for (key, entry) in toTranslate.sorted(by: { $0.key < $1.key }) {
    let localization = (entry["localizations"] as? [String: Any])?[language]
    let units = localization.map { stringUnits(in: $0) } ?? []
    let missingForms = (localization.map { pluralVariations(in: $0) } ?? []).flatMap { forms in
        pluralForms.filter { !forms.contains($0) }
    }
    if units.isEmpty {
        problems.append("\(catalogPath): “\(key)” has no translation into \(language).")
    } else if units.contains(where: { $0["state"] as? String != "translated" }) {
        problems.append("\(catalogPath): “\(key)” has a translation into \(language) that is not in state translated.")
    } else if units.contains(where: { ($0["value"] as? String ?? "").isEmpty }) {
        problems.append("\(catalogPath): “\(key)” has an empty translation into \(language).")
    } else if !missingForms.isEmpty {
        let forms = Set(missingForms).sorted().joined(separator: ", ")
        problems.append("\(catalogPath): “\(key)” lacks the plural form \(forms) in \(language).")
    }
}

if !problems.isEmpty {
    for problem in problems {
        print("✗ \(problem)")
    }
    exit(1)
}
let keyCount = Set(extracted.map(\.tableKey)).count
print("✓ \(keyCount) keys in \(files.count) files, all in the catalog; \(toTranslate.count) catalog entries to translate, all translated.")
