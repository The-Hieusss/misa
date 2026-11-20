import Foundation

/// Quick math, a tiny parser that only understands numbers,
/// + - * / ^ %, parentheses and a few functions. 
enum Calculator {
    /// Returns nil when the text isn't math, so other abilities can try.
    static func answer(_ raw: String) -> Reply? {
        guard raw.rangeOfCharacter(from: .decimalDigits) != nil else { return nil }
        var s = clean(raw)
        let money = raw.contains("$")

        // Percentage phrases people actually type
        if let m = s.match(#"^(\d+(?:\.\d+)?) ?% (?:of|on) (.+)$"#), let p = Double(m[1]), let x = eval(m[2]) {
            return reply("\(m[1])% of \(fmt(x, money))", p / 100 * x, money)
        }
        if let m = s.match(#"^(\d+(?:\.\d+)?) ?% off (?:of )?(.+)$"#), let p = Double(m[1]), let x = eval(m[2]) {
            let saved = p / 100 * x
            return Reply(text: "\(fmt(x, money)) with \(m[1])% off = \(fmt(x - saved, money))\nYou save \(fmt(saved, money)).")
        }
        if let m = s.match(#"^(?:a )?(\d+(?:\.\d+)?) ?% tip (?:on|for) (.+)$"#) ?? s.match(#"^tip (?:of )?(\d+(?:\.\d+)?) ?% (?:on|for) (.+)$"#),
           let p = Double(m[1]), let x = eval(m[2]) {
            let tip = p / 100 * x
            return Reply(text: "\(m[1])% tip on \(fmt(x, true)) = \(fmt(tip, true))\nTotal: \(fmt(x + tip, true))")
        }
        if let m = s.match(#"^(.+?) (plus|\+|minus|-) (\d+(?:\.\d+)?) ?%(?: tax| discount)?$"#), let x = eval(m[1]), let p = Double(m[3]) {
            let sign: Double = (m[2] == "plus" || m[2] == "+") ? 1 : -1
            return reply("\(fmt(x, money)) \(sign > 0 ? "+" : "−") \(m[3])%", x * (1 + sign * p / 100), money)
        }
        if let m = s.match(#"^what percent(?:age)? of (.+) is (.+)$"#), let b = eval(m[1]), let a = eval(m[2]) {
            return b == 0 ? Reply(text: "That's undefined: the total is zero.") : Reply(text: "\(fmt(a)) is \(fmt(a / b * 100))% of \(fmt(b)).")
        }
        if let m = s.match(#"^(.+) is what percent(?:age)? of (.+)$"#), let a = eval(m[1]), let b = eval(m[2]) {
            return b == 0 ? Reply(text: "That's undefined: the total is zero.") : Reply(text: "\(fmt(a)) is \(fmt(a / b * 100))% of \(fmt(b)).")
        }

        // Plain expressions: "84.5 * 1.15", "sqrt(2) ^ 3", "12 divided by 5"
        s = words(s)
        guard s.rangeOfCharacter(from: CharacterSet(charactersIn: "+-*/^%(")) != nil,
              s.range(of: #"^[0-9a-z.+\-*/^%(), ]+$"#, options: .regularExpression) != nil else { return nil }
        var p = Parser(s)
        do {
            let v = try p.parse()
            return reply(s.replacingOccurrences(of: "*", with: "×").replacingOccurrences(of: "/", with: "÷"), v, money)
        } catch Parser.Failure.divideByZero {
            return Reply(text: "That's undefined: it divides by zero.")
        } catch {
            return nil
        }
    }

    /// Evaluates a sub-expression
    static func eval(_ s: String) -> Double? {
        var p = Parser(words(s))
        return try? p.parse()
    }

    private static func reply(_ question: String, _ value: Double, _ money: Bool) -> Reply {
        guard value.isFinite else { return Reply(text: "That number is too big for me.") }
        return Reply(text: "\(question) = \(fmt(value, money))")
    }

    private static func clean(_ raw: String) -> String {
        var s = raw.lowercased()
            .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "π", with: "pi")
            .replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "(\\d),(\\d{3})", with: "$1$2", options: .regularExpression) // 1,000 → 1000
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        for prefix in ["what is ", "what's ", "whats ", "calculate ", "compute ", "how much is ", "solve ", "evaluate ", "= "] where s.hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
        }
        if s.hasSuffix(" =") { s = String(s.dropLast(2)) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func words(_ s: String) -> String {
        var s = " \(s) "
        let swaps: [(String, String)] = [
            (" plus ", " + "), (" minus ", " - "), (" times ", " * "), (" multiplied by ", " * "),
            (" divided by ", " / "), (" over ", " / "), (" to the power of ", " ^ "), (" mod ", " % "),
            (" squared ", " ^ 2 "), (" cubed ", " ^ 3 "),
        ]
        for (a, b) in swaps { s = s.replacingOccurrences(of: a, with: b) }
        s = s.replacingOccurrences(of: "square root of ([0-9.]+)", with: "sqrt($1)", options: .regularExpression)
        s = s.replacingOccurrences(of: "(\\d) ?x ?(\\d)", with: "$1*$2", options: .regularExpression) // 3 x 4
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Up to 10 significant digits, no trailing zeros; money gets 2 decimals.
    static func fmt(_ v: Double, _ money: Bool = false) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        if money {
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
            return "$" + (f.string(from: NSNumber(value: v)) ?? "\(v)")
        }
        if abs(v) >= 1e15 || (abs(v) < 1e-6 && v != 0) {
            f.numberStyle = .scientific
            f.maximumSignificantDigits = 6
        } else {
            f.usesSignificantDigits = true
            f.maximumSignificantDigits = 10
        }
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    /// Recursive-descent parser: expr → term (± term)*, term → power (×÷% power)*, power → unary (^ power)?
    struct Parser {
        enum Failure: Error { case syntax, divideByZero }
        private let chars: [Character]
        private var i = 0

        init(_ s: String) { chars = Array(s.replacingOccurrences(of: " ", with: "")) }

        mutating func parse() throws -> Double {
            let v = try expr()
            guard i == chars.count else { throw Failure.syntax }
            return v
        }

        private var peek: Character? { i < chars.count ? chars[i] : nil }

        private mutating func eat(_ c: Character) -> Bool {
            if peek == c { i += 1; return true }
            return false
        }

        private mutating func expr() throws -> Double {
            var v = try term()
            while let c = peek, c == "+" || c == "-" {
                i += 1
                let r = try term()
                v = c == "+" ? v + r : v - r
            }
            return v
        }

        private mutating func term() throws -> Double {
            var v = try power()
            while let c = peek, c == "*" || c == "/" || c == "%" {
                i += 1
                let r = try power()
                if c == "*" { v *= r; continue }
                if r == 0 { throw Failure.divideByZero }
                v = c == "/" ? v / r : v.truncatingRemainder(dividingBy: r)
            }
            return v
        }

        private mutating func power() throws -> Double {
            let base = try unary()
            if eat("^") { return Foundation.pow(base, try power()) } // right-associative
            return base
        }

        private mutating func unary() throws -> Double {
            if eat("-") { return -(try unary()) }
            if eat("+") { return try unary() }
            var v = try primary()
            // "20%" at the end of a number means 0.2, unless it's "a % b" (modulo).
            if peek == "%" {
                let next = i + 1 < chars.count ? chars[i + 1] : nil
                if next == nil || !(next!.isNumber || next == "(" || next == ".") { i += 1; v /= 100 }
            }
            return v
        }

        private mutating func primary() throws -> Double {
            if eat("(") {
                let v = try expr()
                guard eat(")") else { throw Failure.syntax }
                return v
            }
            if let c = peek, c.isNumber || c == "." {
                let start = i
                while let d = peek, d.isNumber || d == "." { i += 1 }
                guard let v = Double(String(chars[start..<i])) else { throw Failure.syntax }
                return v
            }
            if let c = peek, c.isLetter {
                let start = i
                while let d = peek, d.isLetter || d.isNumber { i += 1 }
                let name = String(chars[start..<i])
                switch name {
                case "pi": return Double.pi
                case "e": return M_E
                default: break
                }
                guard eat("(") else { throw Failure.syntax }
                var args = [try expr()]
                while eat(",") { args.append(try expr()) }
                guard eat(")") else { throw Failure.syntax }
                switch (name, args.count) {
                case ("sqrt", 1): return args[0].squareRoot()
                case ("abs", 1): return abs(args[0])
                case ("round", 1): return args[0].rounded()
                case ("round", 2): let m = Foundation.pow(10, args[1]); return (args[0] * m).rounded() / m
                case ("ln", 1): return Foundation.log(args[0])
                case ("log", 1): return log10(args[0])
                case ("sin", 1): return Foundation.sin(args[0])
                case ("cos", 1): return Foundation.cos(args[0])
                case ("tan", 1): return Foundation.tan(args[0])
                default: throw Failure.syntax
                }
            }
            throw Failure.syntax
        }
    }
}

extension String {
    /// Regex capture groups (index 0 is the whole match), or nil.
    func match(_ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<m.numberOfRanges).map { idx in
            Range(m.range(at: idx), in: self).map { String(self[$0]) } ?? ""
        }
    }
}
