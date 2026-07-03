import Foundation

public enum LassoError: Error, LocalizedError {
    case missingAPIKey
    case apiError(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No Gemini API key set."
        case .apiError(let message): return "API error: \(message)"
        case .badResponse: return "Unexpected response from the API."
        }
    }
}
