import Foundation

/// Lifetime usage counters + approximate cost, persisted in UserDefaults.
public enum UsageStore {
    static var defaults = UserDefaults.standard

    // USD per 1M tokens, Gemini Flash rates — update if Google changes pricing.
    static let inputCostPer1M = 0.30
    static let outputCostPer1M = 2.50

    private static let countKey = "usage.lassoCount"
    private static let inputKey = "usage.inputTokens"
    private static let outputKey = "usage.outputTokens"

    public static func record(input: Int, output: Int) {
        defaults.set(lassoCount + 1, forKey: countKey)
        defaults.set(inputTokens + input, forKey: inputKey)
        defaults.set(outputTokens + output, forKey: outputKey)
    }

    public static var lassoCount: Int { defaults.integer(forKey: countKey) }
    public static var inputTokens: Int { defaults.integer(forKey: inputKey) }
    public static var outputTokens: Int { defaults.integer(forKey: outputKey) }

    public static var totalCost: Double {
        Double(inputTokens) / 1_000_000 * inputCostPer1M
            + Double(outputTokens) / 1_000_000 * outputCostPer1M
    }

    /// e.g. "42 lassos · ~$0.02 total"
    public static var summary: String {
        let count = lassoCount
        guard count > 0 else { return "No lassos yet" }
        let noun = count == 1 ? "lasso" : "lassos"
        return "\(count) \(noun) · ~\(String(format: "$%.2f", totalCost)) total"
    }

    public static func reset() {
        defaults.removeObject(forKey: countKey)
        defaults.removeObject(forKey: inputKey)
        defaults.removeObject(forKey: outputKey)
    }
}
