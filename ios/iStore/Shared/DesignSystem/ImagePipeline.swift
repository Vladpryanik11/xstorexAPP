import UIKit

/// Загрузка картинок: `NSCache` в памяти + `URLCache` на диске, общие загрузки для одинаковых URL.
actor ImagePipeline {
    static let shared = ImagePipeline()

    private let session: URLSession
    private let memory = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024,
            diskPath: "istore-images"
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        memory.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func image(for url: URL) async throws -> UIImage {
        if let cached = memory.object(forKey: url as NSURL) {
            return cached
        }
        if let task = inFlight[url] {
            return try await task.value
        }
        let session = self.session
        let task = Task<UIImage, Error> {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image.preparingForDisplay() ?? image
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let image = try await task.value
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: url as NSURL, cost: cost)
        return image
    }

    func clearMemory() {
        memory.removeAllObjects()
    }
}

/// `UIImageView`, который грузит картинку по URL и отменяет загрузку при переиспользовании.
final class RemoteImageView: UIImageView {
    private var loadTask: Task<Void, Never>?
    private(set) var currentURL: URL?
    var placeholderColor: UIColor = Palette.skeleton

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = placeholderColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(url: URL?, pipeline: ImagePipeline = .shared) {
        guard url != currentURL || image == nil else { return }
        cancel()
        currentURL = url
        image = nil
        backgroundColor = placeholderColor
        guard let url = url else { return }
        loadTask = Task { [weak self] in
            let image = try? await pipeline.image(for: url)
            guard !Task.isCancelled, let self = self, self.currentURL == url else { return }
            self.image = image
            if image != nil {
                self.backgroundColor = .clear
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    func reset() {
        cancel()
        currentURL = nil
        image = nil
        backgroundColor = placeholderColor
    }
}
