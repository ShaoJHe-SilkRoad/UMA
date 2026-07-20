import AppKit
import Foundation
import Testing

struct UMADemoAssetTests {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test
    func publicationDemoAssetsArePresentSharpAndBounded() throws {
        let expectedDimensions = [
            "uma-dark-collapsed.png": (width: 740, height: 780),
            "uma-dark-expanded.png": (width: 740, height: 1_480),
            "uma-light-collapsed.png": (width: 740, height: 780),
            "uma-settings.png": (width: 740, height: 780),
        ]

        for (name, dimensions) in expectedDimensions {
            let url = repositoryRoot
                .appendingPathComponent("Assets/Demo", isDirectory: true)
                .appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            let bitmap = try #require(NSBitmapImageRep(data: data))

            #expect(bitmap.pixelsWide == dimensions.width)
            #expect(bitmap.pixelsHigh == dimensions.height)
            #expect(data.count < 2_000_000)
            #expect(hasVisibleImageContent(bitmap))
        }
    }

    private func hasVisibleImageContent(_ bitmap: NSBitmapImageRep) -> Bool {
        var sampledColors = Set<UInt32>()
        let columns = 12
        let rows = 12

        for column in 0..<columns {
            for row in 0..<rows {
                let x = column * max(bitmap.pixelsWide - 1, 0) / max(columns - 1, 1)
                let y = row * max(bitmap.pixelsHigh - 1, 0) / max(rows - 1, 1)
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                    continue
                }
                let red = UInt32((color.redComponent * 31).rounded())
                let green = UInt32((color.greenComponent * 31).rounded())
                let blue = UInt32((color.blueComponent * 31).rounded())
                sampledColors.insert((red << 10) | (green << 5) | blue)
            }
        }

        return sampledColors.count >= 12
    }
}
