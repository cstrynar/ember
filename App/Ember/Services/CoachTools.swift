import Foundation
import EmberCore

/// The coach's client-side tools. Each maps a model tool call to `AppModel` / `EmberCore`
/// and returns a string (JSON or a short confirmation) for the model to read.
@MainActor
final class CoachTools {
    private let app: AppModel

    init(app: AppModel) { self.app = app }

    // MARK: Tool definitions (client tools + the server-side web_search tool)

    func definitions() -> [[String: Any]] {
        [
            tool("get_today",
                 "Read today's nutrition (consumed vs goal, food entries), hydration, logged sets, and the user's profile/goal.",
                 properties: [:], required: []),
            tool("get_recent_workouts",
                 "Read recent workouts for progress questions. Returns per-exercise sets, best estimated 1RM, and volume.",
                 properties: ["limit": ["type": "integer", "description": "How many recent workouts (default 8)."]],
                 required: []),
            tool("search_food_database",
                 "Search the local food database by name. Returns matches with food_id and per-serving macros.",
                 properties: ["query": ["type": "string"]], required: ["query"]),
            tool("log_food",
                 "Log a food to today's diary. Provide food_id (from search) OR a name plus per-serving macros.",
                 properties: [
                    "food_id": ["type": "string"],
                    "name": ["type": "string"],
                    "servings": ["type": "number"],
                    "meal": ["type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]],
                    "calories": ["type": "number"], "protein": ["type": "number"],
                    "carbs": ["type": "number"], "fat": ["type": "number"],
                 ],
                 required: ["servings", "meal"]),
            tool("log_set",
                 "Log a workout set. Matches a catalog exercise by name or creates a custom one.",
                 properties: [
                    "exercise": ["type": "string"],
                    "reps": ["type": "integer"],
                    "weight_kg": ["type": "number"],
                 ],
                 required: ["exercise", "reps", "weight_kg"]),
            tool("add_water",
                 "Add to today's hydration total, in milliliters.",
                 properties: ["milliliters": ["type": "integer"]], required: ["milliliters"]),
            tool("get_reminders",
                 "List the recurring meal/water reminders with their ids, times, and on/off state.",
                 properties: [:], required: []),
            tool("set_reminder",
                 "Change one reminder by id: set its hour (0-23), minute (0-59), and/or enabled.",
                 properties: [
                    "id": ["type": "string"],
                    "hour": ["type": "integer"], "minute": ["type": "integer"],
                    "enabled": ["type": "boolean"],
                 ],
                 required: ["id"]),
            tool("append_friction_log",
                 "Record a note when the app or a workflow felt clunky, or some data was missing. These are reviewed weekly to improve Ember.",
                 properties: ["context": ["type": "string"], "note": ["type": "string"]],
                 required: ["note"]),
            tool("remember",
                 "Store, update, or remove a durable fact about the user (diet, goals, what's worked, injuries/limits) that persists across conversations and is shown to you each session. Use action 'add' with text (and optional category) for a new fact; 'update' with an id (from get_today's coach_memory) to revise one; 'remove' with an id to drop one.",
                 properties: [
                    "action": ["type": "string", "enum": ["add", "update", "remove"],
                               "description": "Defaults to 'add'."],
                    "text": ["type": "string", "description": "The fact (required for add; replaces text on update)."],
                    "category": ["type": "string", "description": "Free-text grouping, e.g. diet/goals/injuries. Defaults to 'general'."],
                    "id": ["type": "string", "description": "Memory item id (required for update/remove)."],
                 ],
                 required: []),
            ["type": "web_search_20250305", "name": "web_search", "max_uses": 5],
        ]
    }

    private func tool(_ name: String, _ description: String,
                      properties: [String: Any], required: [String]) -> [String: Any] {
        ["name": name, "description": description,
         "input_schema": ["type": "object", "properties": properties, "required": required]]
    }

    // MARK: Dispatch

    func run(name: String, input: [String: Any]) -> String {
        switch name {
        case "get_today":             return getToday()
        case "get_recent_workouts":   return getRecentWorkouts(limit: intVal(input, "limit") ?? 8)
        case "search_food_database":  return searchFood(input["query"] as? String ?? "")
        case "log_food":              return logFood(input)
        case "log_set":               return logSet(input)
        case "add_water":             return addWater(input)
        case "get_reminders":         return getReminders()
        case "set_reminder":          return setReminder(input)
        case "append_friction_log":   return appendFriction(input)
        case "remember":              return remember(input)
        default:                      return "Unknown tool: \(name)"
        }
    }

    // MARK: Implementations

    private func getToday() -> String {
        var d: [String: Any] = ["date": app.dayKey]
        if let p = app.profile {
            var profile: [String: Any] = ["sex": p.sex.rawValue, "age": p.age, "height_cm": p.heightCm,
                            "weight_kg": app.currentWeightKg ?? p.weightKg, "activity": p.activity.rawValue,
                            "goal": p.goal.rawValue, "diet": p.dietaryPattern.rawValue, "notes": p.notes,
                            "weight_source": app.healthWeights.isEmpty ? "manual" : "health"]
            if let target = p.goalWeightKg { profile["goal_weight_kg"] = target }
            d["profile"] = profile
        }
        if let g = app.goal {
            d["goal_macros"] = macros(g)
            d["remaining"] = macros(g - app.consumed)
        }
        d["consumed"] = macros(app.consumed)
        d["food_entries"] = app.today.entries.map { e -> [String: Any] in
            ["name": e.name, "meal": e.meal.rawValue, "servings": e.servings,
             "calories": round(e.consumed.calories), "protein": round(e.consumed.proteinG),
             "carbs": round(e.consumed.carbG), "fat": round(e.consumed.fatG)]
        }
        d["hydration_ml"] = app.hydration.milliliters
        d["hydration_target_ml"] = app.hydrationTargetML
        d["today_sets"] = app.todayWorkout.sets.map {
            ["exercise": $0.exerciseName, "reps": $0.reps, "weight_kg": $0.weightKg]
        }
        d["coach_memory"] = app.coachMemory.items.map {
            ["id": $0.id.uuidString, "category": $0.category, "text": $0.text]
        }
        return json(d)
    }

    private func getRecentWorkouts(limit: Int) -> String {
        let recent = app.allWorkouts.sorted { $0.date > $1.date }.prefix(max(1, limit))
        let arr = recent.map { w -> [String: Any] in
            let groups = Dictionary(grouping: w.sets, by: { $0.exerciseID })
            let exercises = groups.map { (_, sets) -> [String: Any] in
                ["exercise": sets.first?.exerciseName ?? "",
                 "best_1rm_kg": round(sets.map(WorkoutProgress.estimatedOneRepMax).max() ?? 0),
                 "volume_kg": round(WorkoutProgress.volume(of: sets)),
                 "sets": sets.map { ["reps": $0.reps, "weight_kg": $0.weightKg] }]
            }
            return ["date": w.dayKey, "total_volume_kg": round(WorkoutProgress.volume(of: w.sets)),
                    "exercises": exercises]
        }
        return json(arr)
    }

    private func searchFood(_ query: String) -> String {
        let items = app.foodDatabase.search(query).prefix(8).map { item -> [String: Any] in
            ["food_id": item.id, "name": item.name, "serving": item.servingDescription,
             "calories": round(item.macrosPerServing.calories), "protein": round(item.macrosPerServing.proteinG),
             "carbs": round(item.macrosPerServing.carbG), "fat": round(item.macrosPerServing.fatG)]
        }
        return json(Array(items))
    }

    private func logFood(_ input: [String: Any]) -> String {
        guard let servings = dblVal(input, "servings"),
              let mealStr = input["meal"] as? String, let meal = Meal(rawValue: mealStr) else {
            return "Error: 'servings' (number) and 'meal' (breakfast/lunch/dinner/snack) are required."
        }
        if let id = input["food_id"] as? String, let item = app.foodDatabase.item(id: id) {
            app.log(item, servings: servings, meal: meal)
            return "Logged \(formatServings(servings))× \(item.name) to \(meal.rawValue)."
        }
        let name = (input["name"] as? String) ?? "Food"
        let m = Macros(calories: dblVal(input, "calories") ?? 0, proteinG: dblVal(input, "protein") ?? 0,
                       carbG: dblVal(input, "carbs") ?? 0, fatG: dblVal(input, "fat") ?? 0)
        app.logManual(name: name, macros: m, servings: servings, meal: meal, saveToLibrary: false)
        return "Logged \(formatServings(servings))× \(name) to \(meal.rawValue)."
    }

    private func logSet(_ input: [String: Any]) -> String {
        guard let name = input["exercise"] as? String,
              let reps = intVal(input, "reps"), let weight = dblVal(input, "weight_kg") else {
            return "Error: 'exercise', 'reps', and 'weight_kg' are required."
        }
        let exercise = app.exerciseCatalog.first { $0.name.lowercased() == name.lowercased() }
            ?? app.makeCustomExercise(named: name)
        app.logSet(exercise: exercise, reps: reps, weightKg: weight)
        return "Logged \(reps) × \(formatServings(weight)) kg \(exercise.name)."
    }

    private func addWater(_ input: [String: Any]) -> String {
        guard let ml = intVal(input, "milliliters") else { return "Error: 'milliliters' (integer) is required." }
        app.addWater(ml)
        return "Added \(ml) ml. Today's total: \(app.hydration.milliliters) ml."
    }

    private func getReminders() -> String {
        json(app.reminderSettings.reminders.map {
            ["id": $0.id, "label": $0.label, "hour": $0.hour, "minute": $0.minute, "enabled": $0.enabled]
        })
    }

    private func setReminder(_ input: [String: Any]) -> String {
        guard let id = input["id"] as? String else { return "Error: 'id' is required (see get_reminders)." }
        var settings = app.reminderSettings
        guard let idx = settings.reminders.firstIndex(where: { $0.id == id }) else {
            return "No reminder with id '\(id)'. Use get_reminders to list valid ids."
        }
        if let h = intVal(input, "hour") { settings.reminders[idx].hour = min(23, max(0, h)) }
        if let m = intVal(input, "minute") { settings.reminders[idx].minute = min(59, max(0, m)) }
        if let e = input["enabled"] as? Bool { settings.reminders[idx].enabled = e }
        app.updateReminders(settings)
        let r = settings.reminders[idx]
        return "Updated '\(r.id)': \(r.timeString), \(r.enabled ? "on" : "off")."
    }

    private func appendFriction(_ input: [String: Any]) -> String {
        let note = (input["note"] as? String) ?? ""
        guard !note.isEmpty else { return "Error: 'note' is required." }
        app.logFriction(context: (input["context"] as? String) ?? "general", note: note)
        return "Noted in the friction log."
    }

    private func remember(_ input: [String: Any]) -> String {
        let action = (input["action"] as? String) ?? "add"
        switch action {
        case "add":
            guard let text = (input["text"] as? String), !text.isEmpty else {
                return "Error: 'text' is required to add a memory."
            }
            let category = (input["category"] as? String) ?? "general"
            let memory = app.rememberFact(category: category, text: text)
            return "Saved. \(memory.items.count) fact\(memory.items.count == 1 ? "" : "s") in memory."
        case "update":
            guard let idStr = input["id"] as? String, let id = UUID(uuidString: idStr) else {
                return "Error: a valid 'id' is required to update a memory (see get_today's coach_memory)."
            }
            let category = input["category"] as? String
            let text = input["text"] as? String
            guard category != nil || text != nil else {
                return "Error: provide 'text' and/or 'category' to update."
            }
            let memory = app.updateFact(id: id, category: category, text: text)
            return "Updated. \(memory.items.count) fact\(memory.items.count == 1 ? "" : "s") in memory."
        case "remove":
            guard let idStr = input["id"] as? String, let id = UUID(uuidString: idStr) else {
                return "Error: a valid 'id' is required to remove a memory (see get_today's coach_memory)."
            }
            let memory = app.removeFact(id: id)
            return "Removed. \(memory.items.count) fact\(memory.items.count == 1 ? "" : "s") in memory."
        default:
            return "Error: 'action' must be one of add, update, remove."
        }
    }

    // MARK: Helpers

    private func macros(_ m: Macros) -> [String: Any] {
        ["calories": round(m.calories), "protein": round(m.proteinG),
         "carbs": round(m.carbG), "fat": round(m.fatG)]
    }

    private func round(_ v: Double) -> Int { Int(v.rounded()) }

    private func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private func dblVal(_ input: [String: Any], _ key: String) -> Double? {
        if let d = input[key] as? Double { return d }
        if let i = input[key] as? Int { return Double(i) }
        if let n = input[key] as? NSNumber { return n.doubleValue }
        if let s = input[key] as? String { return Double(s) }
        return nil
    }

    private func intVal(_ input: [String: Any], _ key: String) -> Int? {
        if let i = input[key] as? Int { return i }
        if let d = input[key] as? Double { return Int(d) }
        if let n = input[key] as? NSNumber { return n.intValue }
        if let s = input[key] as? String { return Int(s) }
        return nil
    }
}
