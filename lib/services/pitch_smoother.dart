import 'dart:collection';

/// Median-filter pitch smoother over a rolling window.
class PitchSmoother {
	final int windowSize;
	final List<double> _window = <double>[];

	PitchSmoother({int windowSize = 5}) : windowSize = windowSize.clamp(1, 99);

	/// Add a new pitch estimate (Hz). If null, the window is unchanged.
	/// Returns the current smoothed pitch (median) or null if window is empty.
	double? add(double? pitchHz) {
		if (pitchHz != null && pitchHz.isFinite && pitchHz > 0) {
			_window.add(pitchHz);
			if (_window.length > windowSize) {
				_window.removeAt(0);
			}
		}
		if (_window.isEmpty) return null;
		final List<double> sorted = List<double>.from(_window)..sort();
		final int mid = sorted.length ~/ 2;
		if (sorted.length.isOdd) return sorted[mid];
		return 0.5 * (sorted[mid - 1] + sorted[mid]);
	}

	/// Clears internal state.
	void reset() {
		_window.clear();
	}
} 