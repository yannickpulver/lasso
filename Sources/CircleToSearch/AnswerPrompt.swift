import Foundation

/// Shared prompt for all answer providers — Lens-style context, not transcription.
enum AnswerPrompt {
    static let text = """
    The user circled something on their screen and wants context about it — not a transcription.
    Identify the subject and answer what they most likely want to know:
    - a place, building, or landmark → what it is and where
    - a product → what it is, the brand, a rough price
    - a person, artwork, plant, or animal → who or what it is
    - foreign-language text → the translation and meaning
    - a chart, error message, or UI → what it means
    Use web search when it helps. Be concise (2–5 sentences). Do not describe the image itself.
    """
}
