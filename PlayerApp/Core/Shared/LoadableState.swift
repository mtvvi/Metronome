enum LoadableState<Value: Sendable>: Sendable {
    case idle
    case loading(previous: Value?)
    case loaded(Value)
    case failed(AppError, previous: Value?)

    var currentValue: Value? {
        switch self {
        case .idle:
            nil
        case .loading(let previous), .failed(_, let previous):
            previous
        case .loaded(let value):
            value
        }
    }

    var error: AppError? {
        guard case .failed(let error, _) = self else { return nil }
        return error
    }

    var isLoading: Bool {
        guard case .loading = self else { return false }
        return true
    }
}
