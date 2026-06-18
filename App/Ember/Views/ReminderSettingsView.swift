import SwiftUI
import EmberCore

/// Toggle and re-time the recurring meal & hydration reminders. Changes persist and
/// reschedule immediately.
struct ReminderSettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var settings: ReminderSettings = .default

    var body: some View {
        List {
            Section {
                ForEach($settings.reminders) { $reminder in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(reminder.label, isOn: $reminder.enabled)
                        if reminder.enabled {
                            DatePicker("Time", selection: timeBinding(for: $reminder),
                                       displayedComponents: .hourAndMinute)
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text("Reminders are local notifications and never leave your device.")
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { settings = model.reminderSettings }
        .onChange(of: settings) { newValue in
            model.updateReminders(newValue)
        }
    }

    /// Bridges a reminder's hour/minute to the `Date` a `DatePicker` expects.
    private func timeBinding(for reminder: Binding<DailyReminder>) -> Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.year = 2000; c.month = 1; c.day = 1
                c.hour = reminder.wrappedValue.hour
                c.minute = reminder.wrappedValue.minute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                reminder.wrappedValue.hour = c.hour ?? 0
                reminder.wrappedValue.minute = c.minute ?? 0
            }
        )
    }
}
