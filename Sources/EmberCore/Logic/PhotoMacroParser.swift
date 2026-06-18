import Foundation

// MARK: - Expected vision response contract
//
// The photo-macros flow asks a Claude vision call to estimate the food in a photo and reply
// with a single JSON object of the shape below (Stage 3 owns the prompt wording that elicits
// it; Stage 2 only fixes and parses this contract). The JSON may be wrapped in prose or a
// ```json fenced code block — the parser extracts the first balanced `{ … }` span.
//
//   {
//     "items": [
//       { "name": "Grilled chicken breast", "serving": "1 breast (~170g)",
//         "calories": 280, "protein_g": 52, "carb_g": 0, "fat_g": 6 }
//     ],
//     "assumptions": "Assumed no added oil; portion estimated from plate size.",
//     "uncertainty": "medium"
//   }
//
// Tolerated per-item aliases: `kcal` (calories), `protein`/`carb`/`carbs`/`fat` (gram fields).
// Tolerated top-level aliases: `note`/`notes` (assumptions). Missing macro numbers default to 0;
// an item with no usable `name` is dropped. See `PhotoMacroParser.parse(_:)`.

/// One estimated food item from a vision response: a name, a human-readable serving description,
/// and the same `Macros` currency the manual food flow uses (treated as per-serving).
public struct EstimatedFoodItem: Codable, Equatable {
    public var name: String
    public var serving: String
    public var macros: Macros

    public init(name: String, serving: String, macros: Macros) {
        self.name = name
        self.serving = serving
        self.macros = macros
    }

    /// Maps this estimate onto a `FoodItem` for logging (the single place the estimate ↔ FoodItem
    /// correspondence is encoded; consumed in Stage 3). Macros become `macrosPerServing`,
    /// `serving` becomes `servingDescription`; `id` and `source` are caller (App) concerns.
    public func asFoodItem(id: String, source: FoodSource = .custom) -> FoodItem {
        FoodItem(id: id, name: name, servingDescription: serving,
                 macrosPerServing: macros, source: source)
    }
}

/// How confident the estimate is, as reported by the model. Closed enum so Stage-3 UI can switch
/// on it deterministically; absent/unrecognized values map to `.unknown`.
public enum EstimateUncertainty: String, Codable, Equatable {
    case low, medium, high, unknown

    /// Maps a raw (possibly absent/garbage) string onto a case, trimming and lowercasing first.
    public init(rawString: String?) {
        guard let trimmed = rawString?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let known = EstimateUncertainty(rawValue: trimmed)
        else {
            self = .unknown
            return
        }
        self = known
    }
}

/// The success payload of a parse: an ordered list of estimated items, a per-result assumptions
/// string (empty when none), and an uncertainty indicator.
public struct PhotoMacroResult: Equatable {
    public var items: [EstimatedFoodItem]
    public var assumptions: String
    public var uncertainty: EstimateUncertainty

    public init(items: [EstimatedFoodItem], assumptions: String,
                uncertainty: EstimateUncertainty) {
        self.items = items
        self.assumptions = assumptions
        self.uncertainty = uncertainty
    }
}

/// Why a parse failed. Typed so the failure never crosses the API boundary as a throw/crash.
public enum PhotoMacroParseError: Equatable {
    /// No balanced JSON object could be found in the raw text.
    case notJSON
    /// A JSON object was found but decoding the expected shape failed.
    case malformed
    /// JSON parsed, but produced zero usable items (absent/empty `items`, or all items nameless).
    case noItems
}

/// The parser's public return type: a typed success/failure (never a thrown error).
public enum PhotoMacroEstimate: Equatable {
    case success(PhotoMacroResult)
    case failure(PhotoMacroParseError)
}

// MARK: - Wire DTOs (private, Decodable only)
//
// All of the messy key-tolerance lives here so the public types stay clean. These decode the
// model's reply; mapping DTO → public types (dropping nameless items, clamping macros) happens
// in `PhotoMacroParser.parse(_:)`.

/// One item as it arrives on the wire, with hand-written alias-tolerant decoding.
private struct WireItem: Decodable {
    var name: String?
    var serving: String?
    var calories: Double
    var proteinG: Double
    var carbG: Double
    var fatG: Double

    private enum CodingKeys: String, CodingKey {
        case name
        case serving
        // Calories + aliases.
        case calories, kcal
        // Protein + aliases.
        case proteinG = "protein_g", protein
        // Carb + aliases.
        case carbG = "carb_g", carb, carbs
        // Fat + aliases.
        case fatG = "fat_g", fat
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        serving = try c.decodeIfPresent(String.self, forKey: .serving)
        calories = WireItem.number(in: c, keys: [.calories, .kcal])
        proteinG = WireItem.number(in: c, keys: [.proteinG, .protein])
        carbG = WireItem.number(in: c, keys: [.carbG, .carb, .carbs])
        fatG = WireItem.number(in: c, keys: [.fatG, .fat])
    }

    /// First decodable `Double` among `keys` (numbers may arrive as JSON numbers or strings);
    /// defaults to `0` when none is present/parseable. Missing macros are never a parse failure.
    private static func number(in container: KeyedDecodingContainer<CodingKeys>,
                               keys: [CodingKeys]) -> Double {
        for key in keys {
            if let d = try? container.decodeIfPresent(Double.self, forKey: key) {
                return d
            }
            if let s = try? container.decodeIfPresent(String.self, forKey: key),
               let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return d
            }
        }
        return 0
    }
}

/// The whole response object as it arrives on the wire.
private struct WireResponse: Decodable {
    var items: [WireItem]
    var assumptions: String?
    var uncertainty: String?

    private enum CodingKeys: String, CodingKey {
        case items
        case assumptions, note, notes
        case uncertainty
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A genuinely absent `items` key yields []; a present-but-wrong-type `items` (e.g. a
        // string) throws here so `parse` can report `.malformed` rather than silently `.noItems`.
        items = try c.decodeIfPresent([WireItem].self, forKey: .items) ?? []
        assumptions = WireResponse.firstString(in: c, keys: [.assumptions, .note, .notes])
        uncertainty = try? c.decodeIfPresent(String.self, forKey: .uncertainty)
    }

    /// First non-nil string among `keys` (for the `assumptions`/`note`/`notes` aliases).
    private static func firstString(in container: KeyedDecodingContainer<CodingKeys>,
                                    keys: [CodingKeys]) -> String? {
        for key in keys {
            if let s = try? container.decodeIfPresent(String.self, forKey: key) {
                return s
            }
        }
        return nil
    }
}

// MARK: - Parser

/// Pure, network-free parser turning a vision call's raw assistant text into a typed
/// `PhotoMacroEstimate`. Never throws and never crashes: malformed/partial/non-JSON input
/// degrades into a typed `.failure(...)`. This is the Stage-3 seam — Stage 3 passes
/// `AnthropicResponse.assistantText` straight through and maps `.success` items onto `FoodItem`.
public enum PhotoMacroParser {

    /// Parses the model's reply text into estimated food items + assumptions + uncertainty.
    public static func parse(_ assistantText: String) -> PhotoMacroEstimate {
        // (a) Extract the first balanced `{ … }` object from the raw text (handles prose and
        //     ```json fences).
        guard let jsonData = firstJSONObject(in: assistantText) else {
            return .failure(.notJSON)
        }
        // (b) Decode the expected shape; any decode failure is a typed `.malformed`.
        guard let wire = try? JSONDecoder().decode(WireResponse.self, from: jsonData) else {
            return .failure(.malformed)
        }
        // (c) Map DTO → public types: drop nameless items, clamp macros to >= 0.
        let items: [EstimatedFoodItem] = wire.items.compactMap { raw in
            let name = (raw.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let serving = (raw.serving ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let macros = Macros(calories: max(0, raw.calories),
                                proteinG: max(0, raw.proteinG),
                                carbG: max(0, raw.carbG),
                                fatG: max(0, raw.fatG))
            return EstimatedFoodItem(name: name, serving: serving, macros: macros)
        }
        // (d) No usable items → typed `.noItems`; otherwise success.
        guard !items.isEmpty else { return .failure(.noItems) }
        let assumptions = (wire.assumptions ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(PhotoMacroResult(items: items,
                                         assumptions: assumptions,
                                         uncertainty: EstimateUncertainty(rawString: wire.uncertainty)))
    }

    /// Finds the first balanced-brace `{ … }` object in `text` and returns it as UTF-8 `Data`,
    /// or `nil` if there is no balanced object. Scans brace depth while skipping braces inside
    /// JSON string literals (honoring `\"` escapes), so prose- or fence-wrapped JSON is handled.
    private static func firstJSONObject(in text: String) -> Data? {
        let chars = Array(text)
        guard let start = chars.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        while i < chars.count {
            let ch = chars[i]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
            } else {
                switch ch {
                case "\"": inString = true
                case "{":  depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(chars[start...i]).data(using: .utf8)
                    }
                default: break
                }
            }
            i += 1
        }
        return nil // Unbalanced — no closing brace for the first `{`.
    }
}
