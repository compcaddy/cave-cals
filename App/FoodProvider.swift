import Foundation
import Observation

struct FoodResult: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var brand: String?
    var calories: Double
    var servingDescription: String
    var barcode: String?
    var draft: EntryDraft {
        var value = EntryDraft(name: [brand, name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), calories: calories)
        value.externalID = id; value.servingDescription = servingDescription; value.barcode = barcode; value.source = "foodSearch"
        return value
    }
}

protocol FoodSearchService: Sendable { func search(query: String) async throws -> [FoodResult] }
protocol BarcodeLookupService: Sendable { func lookup(barcode: String) async throws -> FoodResult? }

enum FoodServiceError: LocalizedError {
    case unavailable, rateLimited
    var errorDescription: String? {
        switch self {
        case .unavailable: "Food search is unavailable. You can still log calories or use your saved foods."
        case .rateLimited: "Food search is busy. Try again shortly, or add calories manually."
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
    private let provider: any FoodSearchService
    private var cache: [String: [FoodResult]] = [:]
    private let cacheURL: URL?
    init(provider: any FoodSearchService = OpenFoodFacts.shared, persistCache: Bool = true) {
        self.provider = provider
        cacheURL = persistCache ? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("FoodSearchCache.json") : nil
        if let cacheURL, let data = try? Data(contentsOf: cacheURL), let values = try? JSONDecoder().decode([String: [FoodResult]].self, from: data) { cache = values }
    }
    func search(_ text: String) async {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        message = nil; results = cache[query] ?? []; loading = false
        guard query.count >= 2, Double(query) == nil else { return }
        if cache[query] != nil { return }
        loading = true
        do {
            try await Task.sleep(for: .milliseconds(450))
            let values = try await provider.search(query: query)
            try Task.checkCancellation()
            results = values; loading = false
            cache[query] = values
            if cache.count > 150 { cache.removeValue(forKey: cache.keys.sorted().first!) }
            if let cacheURL, let data = try? JSONEncoder().encode(cache) { try? data.write(to: cacheURL, options: .atomic) }
        } catch {
            guard !Task.isCancelled else { return }
            loading = false; message = (error as? FoodServiceError)?.localizedDescription ?? FoodServiceError.unavailable.localizedDescription
        }
    }
}
