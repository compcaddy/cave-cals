import Foundation
import Observation

struct FoodResult: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var brand: String?
    var calories: Double
    var servingDescription: String
    var barcode: String?
    var draft: EntryDraft {
        let displayName = brand.flatMap { brand in
            !brand.isEmpty && name.range(of: brand, options: .caseInsensitive) == nil ? "\(brand) — \(name)" : nil
        } ?? name
        var value = EntryDraft(name: displayName, calories: calories)
        value.externalID = id; value.servingDescription = servingDescription; value.barcode = barcode; value.source = "foodSearch"
        return value
    }
}

struct FoodSearchPage: Decodable, Sendable {
    let results: [FoodResult]
    let cacheLifetime: TimeInterval
}
protocol FoodSearchService: Sendable {
    func search(query: String) async throws -> [FoodResult]
    func searchPage(query: String) async throws -> FoodSearchPage
}
extension FoodSearchService {
    func searchPage(query: String) async throws -> FoodSearchPage {
        FoodSearchPage(results: try await search(query: query), cacheLifetime: 3600)
    }
}

/// Credentials live only on the backend. Search remains free and independent of paid AI access.
actor FatSecretSearch: FoodSearchService {
    static let shared = FatSecretSearch()
    private let session: URLSession
    private let baseURL: URL
    init(session: URLSession = .shared, baseURL: URL = AIConfiguration.baseURL ?? AIConfiguration.productionURL) {
        self.session = session; self.baseURL = baseURL
    }
    func search(query: String) async throws -> [FoodResult] { try await searchPage(query: query).results }
    func searchPage(query: String) async throws -> FoodSearchPage {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/foods/search"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["query": query])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FoodServiceError.unavailable }
        if http.statusCode == 429 { throw FoodServiceError.rateLimited }
        guard (200...299).contains(http.statusCode) else { throw FoodServiceError.unavailable }
        let page = try JSONDecoder().decode(FoodSearchPage.self, from: data)
        guard page.cacheLifetime.isFinite, page.cacheLifetime >= 0,
              page.results.allSatisfy({ $0.id.hasPrefix("fatsecret:") && !$0.name.isEmpty && !$0.servingDescription.isEmpty && $0.calories.isFinite && $0.calories >= 0 && $0.calories <= 100_000 }) else {
            throw FoodServiceError.unavailable
        }
        return page
    }
}
protocol BarcodeLookupService: Sendable { func lookup(barcode: String) async throws -> FoodResult? }

enum FoodServiceError: LocalizedError {
    case unavailable, rateLimited, serverUnavailable, offline, timedOut
    var errorDescription: String? {
        switch self {
        case .unavailable: "Food search is unavailable. You can still log calories or use your saved foods."
        case .rateLimited: "Food search is busy. Try again shortly, or add calories manually."
        case .serverUnavailable: "Open Food Facts is temporarily unavailable. Try again shortly. You can still log calories or use saved foods."
        case .offline: "Food search couldn’t connect. Check your internet connection. You can still log calories or use saved foods."
        case .timedOut: "Food search took too long to respond. Try again shortly. You can still log calories or use saved foods."
        }
    }
}

actor OpenFoodFacts: FoodSearchService, BarcodeLookupService {
    static let shared = OpenFoodFacts()
    private let session: URLSession
    private var searchTimes: [Date] = []
    private var lookupTimes: [Date] = []
    private let fields = "code,product_name,brands,serving_size,serving_quantity,nutriments,quantity"
    init(session: URLSession = .shared) { self.session = session }
    private func request(path: String, query: [URLQueryItem] = []) -> URLRequest {
        var url = URLComponents(string: "https://world.openfoodfacts.org\(path)")!
        url.queryItems = query + [URLQueryItem(name: "fields", value: fields)]
        var request = URLRequest(url: url.url!, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("CaveCals2/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        return request
    }
    private func data(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FoodServiceError.unavailable }
        if http.statusCode == 429 { throw FoodServiceError.rateLimited }
        if (500...599).contains(http.statusCode) { throw FoodServiceError.serverUnavailable }
        guard (200...299).contains(http.statusCode) else { throw FoodServiceError.unavailable }
        return data
    }
    func search(query: String) async throws -> [FoodResult] {
        // Conservative rolling budget; cancellation does not reset the quota.
        searchTimes.removeAll { Date().timeIntervalSince($0) > 60 }
        if searchTimes.count >= 9 { throw FoodServiceError.rateLimited }
        if let last = searchTimes.last {
            let delay = 6.5 - Date().timeIntervalSince(last)
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        }
        try Task.checkCancellation(); searchTimes.append(Date())
        let response = try await data(request(path: "/cgi/search.pl", query: [
            .init(name: "search_terms", value: query), .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"), .init(name: "json", value: "1"),
            .init(name: "page_size", value: "25")
        ]))
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: response)
        var seen = Set<String>()
        return decoded.products.compactMap(\.result).filter { seen.insert($0.id).inserted }
    }
    func lookup(barcode: String) async throws -> FoodResult? {
        lookupTimes.removeAll { Date().timeIntervalSince($0) > 60 }
        guard lookupTimes.count < 14 else { throw FoodServiceError.rateLimited }
        lookupTimes.append(Date())
        let response = try await data(request(path: "/api/v3/product/\(barcode).json"))
        return try JSONDecoder().decode(ProductResponse.self, from: response).product?.result
    }

    struct SearchResponse: Decodable { var products: [Product] }
    struct ProductResponse: Decodable { var product: Product? }
    struct FlexibleNumber: Decodable {
        var value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            value = (try? c.decode(Double.self)) ?? (try? c.decode(String.self)).flatMap(Double.init)
        }
    }
    struct Product: Decodable {
        var code: String?
        var product_name: String?
        var brands: String?
        var serving_size: String?
        var serving_quantity: FlexibleNumber?
        var nutriments: [String: FlexibleNumber]?
        var result: FoodResult? {
            guard let code, let name = product_name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            let n = nutriments ?? [:]
            let kcalServing = n["energy-kcal_serving"]?.value ?? n["energy_serving"]?.value.map { $0 / 4.184 }
            let kcal100 = n["energy-kcal_100g"]?.value ?? n["energy_100g"]?.value.map { $0 / 4.184 }
            var calories: Double?
            var description = serving_size ?? ""
            if !description.isEmpty, let kcalServing { calories = kcalServing }
            else if !description.isEmpty, let quantity = serving_quantity?.value, quantity > 0, let kcal100 { calories = kcal100 * quantity / 100 }
            else if let kcal100 { calories = kcal100; description = "100 g / 100 ml" }
            guard let calories, calories.isFinite, calories >= 0, calories <= 100_000 else { return nil }
            return FoodResult(id: "openfoodfacts:\(code)", name: name, brand: brands, calories: calories, servingDescription: description, barcode: code)
        }
    }
}

@MainActor @Observable final class FoodSearchState {
    var results: [FoodResult] = []
    var loading = false
    var message: String?
    private struct Cached: Codable { let results: [FoodResult]; let expiresAt: Date }
    private let provider: any FoodSearchService
    private var cache: [String: Cached] = [:]
    private let cacheURL: URL?
    private let now: () -> Date
    private let debounce: Duration
    private var requestID = UUID()
    init(provider: any FoodSearchService = FatSecretSearch.shared, persistCache: Bool = true,
         cacheURL: URL? = nil, now: @escaping () -> Date = Date.init, debounce: Duration = .milliseconds(450)) {
        self.provider = provider; self.now = now; self.debounce = debounce
        self.cacheURL = persistCache ? (cacheURL ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("FoodSearchCache-v2.json")) : nil
        if let url = self.cacheURL, let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String: Cached].self, from: data) {
            cache = values.filter { !$0.value.results.isEmpty && $0.value.expiresAt > now() && $0.value.expiresAt <= now().addingTimeInterval(3600) }
            persist()
        }
    }
    private func persist() {
        if let cacheURL, let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
    }
    func search(_ text: String) async {
        let id = UUID(); requestID = id
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        cache = cache.filter { !$0.value.results.isEmpty && $0.value.expiresAt > now() }
        persist()
        message = nil; results = []; loading = false
        guard query.count >= 2, Double(query) == nil else { return }
        if let hit = cache[query] { results = hit.results; return }
        loading = true
        defer { if requestID == id { loading = false } }
        do {
            try await Task.sleep(for: debounce)
            let page = try await provider.searchPage(query: query)
            try Task.checkCancellation()
            guard requestID == id else { return }
            results = page.results
            if page.results.isEmpty {
                message = "No online matches. Try a dish name, or add calories manually."
            } else if page.cacheLifetime > 0 {
                cache[query] = Cached(results: page.results, expiresAt: now().addingTimeInterval(min(page.cacheLifetime, 3600)))
                if cache.count > 150, let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key { cache.removeValue(forKey: oldest) }
            }
            // Never cache an empty response or a provider error. Basic FatSecret results aren't cached.
            persist()
        } catch {
            guard !Task.isCancelled, requestID == id else { return }
            if let error = error as? URLError {
                message = (error.code == .timedOut ? FoodServiceError.timedOut : .offline).localizedDescription
            } else {
                message = (error as? FoodServiceError)?.localizedDescription ?? FoodServiceError.unavailable.localizedDescription
            }
        }
    }
}
