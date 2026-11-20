import Foundation

/// "3 cups in ml", "72 f to c", "how many km in 5 miles". Uses Foundation's Measurement, so the
/// conversion factors come from Apple, not from the model.
enum UnitConverter {
    static func answer(_ raw: String) -> Reply? {
        let s = raw.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "(\\d),(\\d{3})", with: "$1$2", options: .regularExpression)
            .replacingOccurrences(of: "\\b(degrees?|deg)\\b ?", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let num = #"(-?\d+(?:\.\d+)?|-?\.\d+)"#
        let unit = #"([a-z°/²\. ]+?)"#

        var value: Double?, from = "", to = ""
        if let m = s.match("^(?:convert |what is |what's |whats )?\(num) ?\(unit) (?:to|in|into|as) \(unit)$") {
            value = Double(m[1]); from = m[2]; to = m[3]
        } else if let m = s.match("^how many \(unit) (?:are |is )?(?:in|is|are) \(num) ?\(unit)$") {
            value = Double(m[2]); from = m[3]; to = m[1]
        }
        guard let v = value, let fromUnits = units(from), let toUnits = units(to) else { return nil }

        // Some names are ambiguous ("oz" is weight or volume); pick the pair that fits.
        for f in fromUnits {
            for t in toUnits where family(f) != nil && family(f) == family(t) {
                let result = Measurement(value: v, unit: f).converted(to: t)
                return Reply(text: "\(describe(v, f, from)) = \(describe(result.value, t, to))")
            }
        }
        let a = from.trimmingCharacters(in: .whitespaces), b = to.trimmingCharacters(in: .whitespaces)
        return Reply(text: "I can't convert \(a) to \(b): they measure different things.")
    }

    /// Which kind of quantity a unit measures. (Apple's built-in units are private subclasses,
    /// so comparing exact types would wrongly reject e.g. a custom "day" against built-in "hours".)
    private static func family(_ u: Dimension) -> ObjectIdentifier? {
        let families: [Dimension.Type] = [UnitLength.self, UnitMass.self, UnitVolume.self, UnitTemperature.self, UnitDuration.self,
                                          UnitSpeed.self, UnitArea.self, UnitInformationStorage.self, UnitEnergy.self]
        return families.first { u.isKind(of: $0) }.map { ObjectIdentifier($0) }
    }

    private static func describe(_ v: Double, _ unit: Dimension, _ typed: String) -> String {
        let decimals = unit is UnitTemperature ? 1 : nil
        let number: String
        if let d = decimals {
            let f = NumberFormatter()
            f.maximumFractionDigits = d
            number = f.string(from: NSNumber(value: v)) ?? "\(v)"
        } else {
            number = Calculator.fmt((v * 10000).rounded() / 10000)
        }
        return "\(number) \(label(for: unit, typed: typed, plural: abs(v) != 1))"
    }

    private static func label(for unit: Dimension, typed: String, plural: Bool) -> String {
        if let names = customNames[unit.symbol], unit === usCup || unit === usTbsp || unit === usTsp || unit === day || unit === week {
            return plural ? names.1 : names.0
        }
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.unitStyle = .long
        // Format with 2 so we get the plural word, then drop the number.
        let word = f.string(from: Measurement(value: plural ? 2 : 1, unit: unit))
            .replacingOccurrences(of: "^[0-9.,]+ ", with: "", options: .regularExpression)
        return word.isEmpty ? typed.trimmingCharacters(in: .whitespaces) : word
    }

    private static func units(_ name: String) -> [Dimension]? {
        let key = name.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: ".", with: "")
        if let u = table[key] { return u }
        if key.hasSuffix("s"), let u = table[String(key.dropLast())] { return u } // "miles" → "mile"
        if key.hasSuffix("es"), let u = table[String(key.dropLast(2))] { return u } // "inches" → "inch"
        return nil
    }

    // US kitchen measures (Apple's built-in cup/tbsp/tsp are metric: 240/15/5 mL).
    private static let usCup = UnitVolume(symbol: "cup", converter: UnitConverterLinear(coefficient: 0.2365882365))
    private static let usTbsp = UnitVolume(symbol: "tbsp", converter: UnitConverterLinear(coefficient: 0.01478676478))
    private static let usTsp = UnitVolume(symbol: "tsp", converter: UnitConverterLinear(coefficient: 0.00492892159))
    /// Names for the units defined here, which MeasurementFormatter doesn't know.
    private static let customNames: [String: (String, String)] = [
        "cup": ("cup", "cups"), "tbsp": ("tablespoon", "tablespoons"), "tsp": ("teaspoon", "teaspoons"),
        "d": ("day", "days"), "wk": ("week", "weeks"),
    ]

    private static let day = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86400))
    private static let week = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))

    private static let table: [String: [Dimension]] = {
        var t: [String: [Dimension]] = [:]
        func add(_ names: [String], _ units: Dimension...) { names.forEach { t[$0] = units } }
        // Length
        add(["mm", "millimeter", "millimetre"], UnitLength.millimeters)
        add(["cm", "centimeter", "centimetre"], UnitLength.centimeters)
        add(["m", "meter", "metre"], UnitLength.meters)
        add(["km", "kilometer", "kilometre"], UnitLength.kilometers)
        add(["in", "inch", "\""], UnitLength.inches)
        add(["ft", "foot", "feet", "'"], UnitLength.feet)
        add(["yd", "yard"], UnitLength.yards)
        add(["mi", "mile"], UnitLength.miles)
        // Mass (and ounces may also mean fluid ounces)
        add(["mg", "milligram"], UnitMass.milligrams)
        add(["g", "gram", "gr"], UnitMass.grams)
        add(["kg", "kilo", "kilogram"], UnitMass.kilograms)
        add(["lb", "lbs", "pound"], UnitMass.pounds)
        add(["oz", "ounce"], UnitMass.ounces, UnitVolume.fluidOunces)
        add(["ton"], UnitMass.shortTons)
        add(["tonne", "metric ton"], UnitMass.metricTons)
        add(["stone", "st"], UnitMass.stones)
        // Volume
        add(["ml", "milliliter", "millilitre"], UnitVolume.milliliters)
        add(["l", "liter", "litre"], UnitVolume.liters)
        add(["cup", "c"], usCup, UnitTemperature.celsius)
        add(["tbsp", "tablespoon"], usTbsp)
        add(["tsp", "teaspoon"], usTsp)
        add(["fl oz", "fluid ounce", "floz"], UnitVolume.fluidOunces)
        add(["pint", "pt"], UnitVolume.pints)
        add(["quart", "qt"], UnitVolume.quarts)
        add(["gallon", "gal"], UnitVolume.gallons)
        // Temperature ("c" is shared with cups above)
        add(["celsius", "centigrade"], UnitTemperature.celsius)
        add(["f", "fahrenheit"], UnitTemperature.fahrenheit)
        add(["kelvin"], UnitTemperature.kelvin)
        // Time
        add(["ms", "millisecond"], UnitDuration.milliseconds)
        add(["s", "sec", "second"], UnitDuration.seconds)
        add(["min", "minute"], UnitDuration.minutes)
        add(["h", "hr", "hour"], UnitDuration.hours)
        add(["day"], day)
        add(["week", "wk"], week)
        // Speed
        add(["mph", "miles per hour", "mi/h"], UnitSpeed.milesPerHour)
        add(["kph", "km/h", "kmh", "kilometers per hour"], UnitSpeed.kilometersPerHour)
        add(["m/s", "meters per second"], UnitSpeed.metersPerSecond)
        add(["knot", "kn"], UnitSpeed.knots)
        // Area
        add(["sq ft", "square feet", "square foot", "ft²", "sqft"], UnitArea.squareFeet)
        add(["sq m", "square meter", "square metre", "m²", "sqm"], UnitArea.squareMeters)
        add(["sq mi", "square mile"], UnitArea.squareMiles)
        add(["sq km", "square kilometer", "km²"], UnitArea.squareKilometers)
        add(["acre"], UnitArea.acres)
        add(["hectare", "ha"], UnitArea.hectares)
        // Data
        add(["bit"], UnitInformationStorage.bits)
        add(["byte", "b"], UnitInformationStorage.bytes)
        add(["kb", "kilobyte"], UnitInformationStorage.kilobytes)
        add(["mb", "megabyte"], UnitInformationStorage.megabytes)
        add(["gb", "gig", "gigabyte"], UnitInformationStorage.gigabytes)
        add(["tb", "terabyte"], UnitInformationStorage.terabytes)
        // Energy
        add(["cal", "calorie", "kcal", "kilocalorie"], UnitEnergy.kilocalories)
        add(["kj", "kilojoule"], UnitEnergy.kilojoules)
        add(["j", "joule"], UnitEnergy.joules)
        return t
    }()
}
