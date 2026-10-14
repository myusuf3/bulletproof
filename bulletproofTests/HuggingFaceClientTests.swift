import Foundation
import Testing
@testable import bulletproof

struct HuggingFaceClientTests {
    private func client(status: Int, json: String) -> HuggingFaceClient {
        var client = HuggingFaceClient()
        client.fetch = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            return (Data(json.utf8), response)
        }
        return client
    }

    @Test func listsFilesAndFiltersDotfiles() async throws {
        let json = """
        {"siblings": [
            {"rfilename": ".gitattributes", "size": 1570},
            {"rfilename": "config.json", "size": 993},
            {"rfilename": "model.safetensors", "size": 5199450666}
        ]}
        """
        let files = try await client(status: 200, json: json).listFiles(repo: "org/name")
        #expect(files.map(\.rfilename) == ["config.json", "model.safetensors"])
        #expect(files.compactMap(\.size).reduce(0, +) == 5_199_451_659)
    }

    @Test func missingSizeDecodesAsNil() async throws {
        let json = """
        {"siblings": [{"rfilename": "config.json"}]}
        """
        let files = try await client(status: 200, json: json).listFiles(repo: "org/name")
        #expect(files == [HFFile(rfilename: "config.json", size: nil)])
    }

    @Test func non200Throws() async {
        await #expect(throws: URLError.self) {
            _ = try await client(status: 404, json: "{}").listFiles(repo: "org/missing")
        }
    }

    @Test func listsFilesAtTheRequestedRevision() async throws {
        let requested = RequestLog()
        var client = client(status: 200, json: #"{"siblings": []}"#)
        let respond = client.fetch
        client.fetch = { request in
            await requested.append(request.url!.absoluteString)
            return try await respond(request)
        }
        _ = try await client.listFiles(repo: "org/name", revision: "run8-final")
        #expect(await requested.urls == ["https://huggingface.co/api/models/org/name/revision/run8-final?blobs=true"])
    }

    @Test func buildsDownloadURL() {
        let url = HuggingFaceClient.downloadURL(repo: "mlx-community/Qwen3-8B-4bit", file: "model.safetensors")
        #expect(url.absoluteString == "https://huggingface.co/mlx-community/Qwen3-8B-4bit/resolve/main/model.safetensors")
    }

    @Test func buildsDownloadURLAtARevision() {
        let url = HuggingFaceClient.downloadURL(repo: "org/name", file: "mlx-4bit/config.json", revision: "run8-final")
        #expect(url.absoluteString == "https://huggingface.co/org/name/resolve/run8-final/mlx-4bit/config.json")
    }
}

private actor RequestLog {
    private(set) var urls: [String] = []
    func append(_ url: String) { urls.append(url) }
}
