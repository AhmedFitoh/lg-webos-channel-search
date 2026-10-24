import Foundation

public enum ArabicNormalizer {
    /// Normalizes a channel name or search query for matching while preserving word boundaries.
    /// - Strips Arabic tashkeel (diacritics) and tatweel (`ـ`).
    /// - Unifies Alef variants (`أ`, `إ`, `آ`, `ٱ` → `ا`).
    /// - Unifies Alef Maqsura / Farsi Yeh / Yeh with Hamza (`ى`, `ی`, `ئ` → `ي`).
    /// - Unifies Ta Marbuta (`ة` → `ه`) and Waw with Hamza (`ؤ` → `و`).
    /// - Converts Arabic-Indic (`٠-٩`) and Extended Arabic-Indic (`۰-۹`) digits to ASCII (`0-9`).
    /// - Folds Latin case and diacritics and collapses multiple/non-breaking spaces (`\u{00A0}`).
    public static func normalize(_ input: String) -> String {
        guard !input.isEmpty else { return "" }

        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(input.unicodeScalars.count)

        for scalar in input.unicodeScalars {
            // 1. Strip tatweel (kashida) and Arabic diacritics (tashkeel)
            if isArabicDiacriticOrTatweel(scalar) {
                continue
            }

            // 2. Convert Arabic-Indic and Eastern Arabic-Indic digits to ASCII 0-9
            if let asciiDigit = normalizeDigit(scalar) {
                scalars.append(asciiDigit)
                continue
            }

            // 3. Unify Arabic letter variants
            if let unifiedArabic = unifyArabicLetter(scalar) {
                scalars.append(unifiedArabic)
                continue
            }

            // 4. Normalize all whitespace scalars (including U+00A0 non-breaking space) to ASCII space
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar.value == 0x00A0 {
                scalars.append(" ")
                continue
            }

            scalars.append(scalar)
        }

        // 5. Fold Latin case & Latin diacritics while keeping unified Arabic letters intact
        let intermediate = String(scalars)
        let folded = foldLatinCaseAndDiacritics(intermediate)

        // 6. Collapse consecutive spaces and trim
        return collapseSpaces(folded)
    }

    /// Normalizes only digits (Arabic-Indic / Extended Arabic-Indic -> ASCII) and trims whitespace.
    public static func normalizeChannelNumber(_ input: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in input.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar.value == 0x00A0 {
                continue
            }
            if let digit = normalizeDigit(scalar) {
                result.append(digit)
            } else {
                result.append(scalar)
            }
        }
        return String(result).lowercased()
    }

    private static func isArabicDiacriticOrTatweel(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        if v == 0x0640 { return true } // Tatweel ـ
        if (0x0610...0x061A).contains(v) { return true }
        if (0x064B...0x065F).contains(v) { return true } // Tashkeel (fatha, damma, kasra, shadda, sukun, etc.)
        if v == 0x0670 { return true } // Superscript alef
        if (0x06D6...0x06ED).contains(v) { return true } // Quranic marks
        if v == 0x200C || v == 0x200D || v == 0x200E || v == 0x200F { return true } // Zero-width / bidi marks
        return false
    }

    private static func normalizeDigit(_ scalar: UnicodeScalar) -> UnicodeScalar? {
        let v = scalar.value
        // Standard Arabic-Indic digits: ٠ (0x0660) ... ٩ (0x0669)
        if (0x0660...0x0669).contains(v) {
            return UnicodeScalar(0x0030 + (v - 0x0660))
        }
        // Extended/Eastern Arabic-Indic digits: ۰ (0x06F0) ... ۹ (0x06F9)
        if (0x06F0...0x06F9).contains(v) {
            return UnicodeScalar(0x0030 + (v - 0x06F0))
        }
        return nil
    }

    private static func unifyArabicLetter(_ scalar: UnicodeScalar) -> UnicodeScalar? {
        switch scalar.value {
        // Alef variants: آ (0x0622), أ (0x0623), إ (0x0625), ٱ (0x0671) -> ا (0x0627)
        case 0x0622, 0x0623, 0x0625, 0x0671:
            return UnicodeScalar(0x0627)

        // Ta Marbuta & Heh variants: ة (0x0629), ۀ (0x06C0), ہ (0x06C1) -> ه (0x0647)
        case 0x0629, 0x06C0, 0x06C1:
            return UnicodeScalar(0x0647)

        // Alef Maqsura, Farsi Yeh, Yeh with Hamza: ى (0x0649), ی (0x06CC), ئ (0x0626) -> ي (0x064A)
        case 0x0649, 0x06CC, 0x0626:
            return UnicodeScalar(0x064A)

        // Waw with Hamza: ؤ (0x0624) -> و (0x0648)
        case 0x0624:
            return UnicodeScalar(0x0648)

        // Farsi Kaf: ک (0x06A9) -> ك (0x0643)
        case 0x06A9:
            return UnicodeScalar(0x0643)

        default:
            return nil
        }
    }

    private static func foldLatinCaseAndDiacritics(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        for ch in text {
            let firstScalar = ch.unicodeScalars.first?.value ?? 0
            // Apply Latin diacritic folding only outside the Arabic block (0x0600...0x06FF)
            // so Foundation's diacritic folding doesn't alter unified Arabic letters.
            if (0x0600...0x06FF).contains(firstScalar) {
                output.append(ch)
            } else {
                let folded = String(ch).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                output.append(folded.lowercased())
            }
        }
        return output
    }

    private static func collapseSpaces(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var previousWasSpace = true // trims leading spaces

        for ch in text {
            if ch == " " {
                if !previousWasSpace {
                    result.append(" ")
                    previousWasSpace = true
                }
            } else {
                result.append(ch)
                previousWasSpace = false
            }
        }

        if result.last == " " {
            result.removeLast()
        }
        return result
    }
}
