import Foundation
import Vision
import AppKit
let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("load") }
let H = cg.height, W = cg.width, step = 2000, overlap = 100
var y = 0
while y < H {
  let h = min(step + overlap, H - y)
  let crop = cg.cropping(to: CGRect(x: 0, y: y, width: W, height: h))!
  let req = VNRecognizeTextRequest()
  req.recognitionLevel = .accurate
  req.usesLanguageCorrection = true
  try VNImageRequestHandler(cgImage: crop, options: [:]).perform([req])
  let obs = (req.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }
  print("=== slice y=\(y)")
  for o in obs { if let t = o.topCandidates(1).first { print(t.string) } }
  y += step
}
