class BodySegmentationService {
  /// Web stub: Estimates a hip/lower-body region.
  /// Always returns fallback lower-half region as ML Kit/FFmpeg are not available on web.
  Future<Map<String, double>> estimateHipRect(String videoPath) async {
    // Fallback: lower half
    return { 'x': 0.0, 'y': 0.5, 'w': 1.0, 'h': 0.5 };
  }
}
