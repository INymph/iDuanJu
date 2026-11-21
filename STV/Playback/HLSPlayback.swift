import AVFoundation

/// Plays huangguo HLS (incl. AES-128) through AVPlayer.
/// Playlists are fetched through a resourceLoader so we can attach Referer/Origin/X-User-Agent,
/// and EXT-X-KEY URIs are rewritten to a local scheme that serves the key we already resolved.
final class HLSPlayback: NSObject, AVAssetResourceLoaderDelegate {
    static let plScheme = "stvhls"
    static let keyScheme = "stvkey"

    let headers: [String: String]
    let keyHex: String
    private let queue = DispatchQueue(label: "stv.hls.loader")
    private let session = URLSession(configuration: .default)

    init(headers: [String: String], keyHex: String) {
        self.headers = headers
        self.keyHex = keyHex
    }

    func makeAsset(url: String) -> AVURLAsset? {
        guard var c = URLComponents(string: url) else { return nil }
        let isHLS = url.lowercased().contains(".m3u8") || url.contains("/m3u8/")
        if isHLS { c.scheme = c.scheme == "http" ? Self.plScheme + "-http" : Self.plScheme }
        guard let u = c.url else { return nil }
        let asset = AVURLAsset(url: u, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        if isHLS { asset.resourceLoader.setDelegate(self, queue: queue) }
        return asset
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource req: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = req.request.url, let scheme = url.scheme else { return false }
        if scheme == Self.keyScheme {
            queue.async { [self] in
                guard !req.isCancelled, !req.isFinished else { return }
                guard let key = Bytes.fromHex(keyHex), key.count == 16 else {
                    req.finishLoading(with: URLError(.userAuthenticationRequired))
                    return
                }
                Self.complete(req, bytes: Data(key), type: "public.data")
            }
            return true
        }
        guard scheme.hasPrefix(Self.plScheme), var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        c.scheme = scheme.hasSuffix("-http") ? "http" : "https"
        guard let real = c.url else { return false }
        var r = URLRequest(url: real)
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        session.dataTask(with: r) { [self] data, resp, err in
            queue.async { [self] in
                guard !req.isCancelled, !req.isFinished else { return }
                guard let data, err == nil, let http = resp as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    req.finishLoading(with: err ?? URLError(.badServerResponse))
                    return
                }
                let text = rewrite(HLSAdFilter.apply(String(decoding: data, as: UTF8.self), base: real), base: real)
                Self.complete(req, bytes: Data(text.utf8), type: "public.m3u-playlist")
            }
        }.resume()
        return true
    }

    private static func complete(_ req: AVAssetResourceLoadingRequest, bytes: Data, type: String) {
        req.contentInformationRequest?.contentType = type
        req.contentInformationRequest?.contentLength = Int64(bytes.count)
        req.contentInformationRequest?.isByteRangeAccessSupported = true
        if let request = req.dataRequest {
            let offset = request.currentOffset
            guard offset >= 0, offset <= Int64(bytes.count), request.requestedOffset >= 0,
                  request.requestedOffset <= offset, request.requestedLength >= 0 else {
                req.finishLoading(with: URLError(.badServerResponse))
                return
            }
            let start = Int(offset)
            let remaining = max(0, Int64(request.requestedLength) - (offset - request.requestedOffset))
            let length = request.requestsAllDataToEndOfResource ? bytes.count - start : min(bytes.count - start, Int(remaining))
            if length > 0 { request.respond(with: bytes.subdata(in: start..<(start + length))) }
        }
        req.finishLoading()
    }

    /// Absolutize URIs; nested playlists go back through the loader, keys go to the local key scheme.
    private func rewrite(_ pl: String, base: URL) -> String {
        func abs(_ s: String) -> URL? { URL(string: s, relativeTo: base)?.absoluteURL }
        func via(_ u: URL, _ scheme: String) -> String {
            var c = URLComponents(url: u, resolvingAgainstBaseURL: false)
            c?.scheme = scheme == Self.plScheme && u.scheme == "http" ? Self.plScheme + "-http" : scheme
            return c?.url?.absoluteString ?? u.absoluteString
        }
        var expectPlaylist = false
        return pl.split(separator: "\n", omittingEmptySubsequences: false).map { raw -> String in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.uppercased().hasPrefix("#EXT-X-STREAM-INF") { expectPlaylist = true; return line }
            if line.uppercased().hasPrefix("#EXT-X-KEY") || line.uppercased().hasPrefix("#EXT-X-MEDIA") || line.uppercased().hasPrefix("#EXT-X-MAP") {
                let isKey = line.uppercased().hasPrefix("#EXT-X-KEY")
                guard let m = HTML.groups("URI\\s*=\\s*\"([^\"]+)\"", line), let u = abs(m[1]) else { return line }
                let repl: String
                if isKey { repl = keyHex.isEmpty ? u.absoluteString : Self.keyScheme + "://key" }
                else if line.uppercased().hasPrefix("#EXT-X-MEDIA") { repl = via(u, Self.plScheme) }
                else { repl = u.absoluteString }
                return line.replacingOccurrences(of: m[1], with: repl)
            }
            if line.isEmpty || line.hasPrefix("#") { return line }
            guard let u = abs(line) else { return line }
            defer { expectPlaylist = false }
            return expectPlaylist || u.path.lowercased().hasSuffix(".m3u8") ? via(u, Self.plScheme) : u.absoluteString
        }.joined(separator: "\n")
    }
}
