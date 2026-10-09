import Foundation

@main
struct DateFormattingPerformance {
    static func main() async {
        let dates = (0..<300).map { Date(timeIntervalSince1970: 1_700_000_000 + Double($0 * 3600)) }
        let templates = ["MMMd", "yMMMd", "yMMMdHHmm"]
        for locale in ["en_US", "zh_CN", "ar_SA"] {
            for zone in ["Asia/Shanghai", "America/Los_Angeles"] {
                for template in templates {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: locale)
                    formatter.timeZone = TimeZone(identifier: zone)!
                    formatter.setLocalizedDateFormatFromTemplate(template)
                    for date in dates.prefix(5) {
                        precondition(BiliDateFormatting.string(from: date, template: template,
                            locale: formatter.locale, timeZone: formatter.timeZone) == formatter.string(from: date))
                    }
                }
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let locale = Locale(identifier: index.isMultiple(of: 2) ? "en_US" : "zh_CN")
                    let zone = TimeZone(secondsFromGMT: index.isMultiple(of: 2) ? 0 : 28800)!
                    let formatter = DateFormatter()
                    formatter.locale = locale
                    formatter.timeZone = zone
                    formatter.setLocalizedDateFormatFromTemplate("yMMMdHHmm")
                    let date = dates[index]
                    precondition(BiliDateFormatting.string(from: date, template: "yMMMdHHmm",
                        locale: locale, timeZone: zone) == formatter.string(from: date))
                }
            }
        }
        func median(cached: Bool) -> Double {
            var times: [Double] = []
            for _ in 0..<7 {
                let start = ContinuousClock.now
                for date in dates {
                    let text: String
                    if cached {
                        text = BiliDateFormatting.string(from: date, template: "yMMMdHHmm",
                                                         locale: Locale(identifier: "zh_CN"))
                    } else {
                        let formatter = DateFormatter()
                        formatter.locale = Locale(identifier: "zh_CN")
                        formatter.setLocalizedDateFormatFromTemplate("yMMMdHHmm")
                        text = formatter.string(from: date)
                    }
                    precondition(!text.isEmpty)
                }
                let elapsed = start.duration(to: .now).components
                times.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
            }
            return times.sorted()[3]
        }
        print("PASS Date formatting preserves templates, locales, zones and concurrent isolation")
        print(String(format: "DATE_FORMAT_300_ROWS_MS legacy=%.3f cached=%.3f (7-run medians)",
                     median(cached: false), median(cached: true)))
    }
}
