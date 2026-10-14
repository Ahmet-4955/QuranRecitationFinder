// Ersatz-Modul „Combine“ – NUR für die Kompilierprüfung unter Linux (dort gibt es kein Combine).
// Enthält nur, was AppSettings, HistoryStore und RecognitionViewModel brauchen. Benachrichtigungen
// an die Oberfläche (objectWillChange) entfallen – die Oberfläche wird unter Linux nicht gebaut.

public protocol ObservableObject: AnyObject {}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
