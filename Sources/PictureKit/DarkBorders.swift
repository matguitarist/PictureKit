import CoreGraphics

extension CGImage {
    /// The picture without the dark bars along its edges (the black borders many screenshots and videos are captured
    /// with), up to a fifth of it a side, so dark art itself isn't eaten. Itself when there are none.
    public func trimmingDarkBorders() -> CGImage {
        let (w, h) = (width, height)
        guard w > 8, h > 8,
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data else { return self }
        context.draw(self, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // Rows are top first in the bitmap.
        func isDark(_ x: Int, _ y: Int) -> Bool {
            let i = (y * w + x) * 4
            return pixels[i] < 28 && pixels[i + 1] < 28 && pixels[i + 2] < 28
        }
        // A line counts as a bar when nearly all of it is dark, allowing a stray pixel or two of noise.
        func columnIsBar(_ x: Int) -> Bool { (0..<h).count { isDark(x, $0) } >= h * 98 / 100 }
        func rowIsBar(_ y: Int) -> Bool { (0..<w).count { isDark($0, y) } >= w * 98 / 100 }

        var (left, right, top, bottom) = (0, w - 1, 0, h - 1)
        while left < w / 5, columnIsBar(left) { left += 1 }
        while right > w - 1 - w / 5, columnIsBar(right) { right -= 1 }
        while top < h / 5, rowIsBar(top) { top += 1 }
        while bottom > h - 1 - h / 5, rowIsBar(bottom) { bottom -= 1 }
        guard left > 0 || top > 0 || right < w - 1 || bottom < h - 1 else { return self }
        return cropping(to: CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1)) ?? self
    }
}
