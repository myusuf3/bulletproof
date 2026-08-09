import Foundation

nonisolated struct HFFile: Decodable, Sendable, Equatable {
    let rfilename: String
    let size: Int64?
}

nonisolated struct HuggingFaceClient: Sendable {
    /// Injectable transport so tests can serve canned JSON.
    var fetch: @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }

    private struct RepoInfo: Decodable {
        let siblings: [HFFile]
    }

    /// Lists a repo's files with sizes (?blobs=true populates them), skipping
    /// git metadata dotfiles.
    func listFiles(repo: String) async throws -> [HFFile] {
        let url = URL(string: "https://huggingface.co/api/models/\(repo)?blobs=true")!
        let (data, response) = try await fetch(URLRequest(url: url))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse, userInfo: [
                NSLocalizedDescriptionKey: "Hugging Face returned HTTP \(http.statusCode) for \(repo)."
            ])
        }
        let info = try JSONDecoder().decode(RepoInfo.self, from: data)
        return info.siblings.filter { !$0.rfilename.hasPrefix(".") }
    }

    static func downloadURL(repo: String, file: String) -> URL {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file)")!
    }
}
