import Foundation

enum FuzzyMatch {
    static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a.lowercased())
        let b = Array(b.lowercased())
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        var prev = Array(0 ... n)
        var curr = [Int](repeating: 0, count: n + 1)

        for i in 1 ... m {
            curr[0] = i
            for j in 1 ... n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(
                    prev[j] + 1,
                    curr[j - 1] + 1,
                    prev[j - 1] + cost
                )
            }
            swap(&prev, &curr)
        }
        return prev[n]
    }

    static func suggestions(for query: String, from candidates: [String], maxDistance: Int = 3, limit: Int = 3) -> [String] {
        candidates
            .map { (name: $0, distance: levenshtein(query, $0)) }
            .filter { $0.distance <= maxDistance && $0.distance > 0 }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map(\.name)
    }
}
