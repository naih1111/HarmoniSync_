import 'dart:math' as math;

/// Enhanced median-filter pitch smoother with outlier detection and weighted filtering.
class PitchSmoother {
	final int windowSize;
	final double outlierThreshold; // Standard deviations for outlier detection
	final bool useWeightedMedian; // Whether to use weighted median (recent samples have more weight)
	
	// Circular buffer for efficient operations
	final List<double?> _window;
	int _writeIndex = 0;
	int _currentSize = 0;
	
	// Statistics for outlier detection
	double _runningMean = 0.0;
	double _runningVariance = 0.0;
	int _statsCount = 0;
	int _outlierCount = 0; // Track rejected outliers

	PitchSmoother({
		this.windowSize = 5,
		this.outlierThreshold = 4.0, // Increased from 3.5 for ultra-lenient music detection
		this.useWeightedMedian = true,
	}) : _window = List<double?>.filled(windowSize.clamp(1, 99), null);

	/// Updates running statistics for outlier detection.
	void _updateStatistics(double value) {
		_statsCount++;
		final double delta = value - _runningMean;
		_runningMean += delta / _statsCount;
		final double delta2 = value - _runningMean;
		_runningVariance += delta * delta2;
	}
	
	/// Checks if a value is an outlier based on running statistics.
	bool _isOutlier(double value) {
		if (_statsCount < 15) return false; // Need many more samples for stable musical stats
		
		final double variance = _runningVariance / (_statsCount - 1);
		final double stdDev = math.sqrt(math.max(variance, 1e-10));
		final double deviation = (value - _runningMean).abs();
		
		// Ultra-conservative threshold for musical pitch detection
		// Accept almost all pitch variations as valid musical expression
		final double adaptiveThreshold = outlierThreshold * 0.2; // Ultra conservative
		
		return deviation > adaptiveThreshold * stdDev;
	}
	
	/// Calculates weighted median giving more weight to recent samples.
	double _calculateWeightedMedian(List<double> values) {
		if (values.isEmpty) return 0.0;
		if (values.length == 1) return values[0];
		
		// Create weighted pairs (value, weight)
		final List<MapEntry<double, double>> weightedValues = [];
		for (int i = 0; i < values.length; i++) {
			// More recent samples get higher weight (exponential decay)
			final double weight = math.exp(-0.3 * (values.length - 1 - i));
			weightedValues.add(MapEntry(values[i], weight));
		}
		
		// Sort by value
		weightedValues.sort((a, b) => a.key.compareTo(b.key));
		
		// Find weighted median
		final double totalWeight = weightedValues.fold(0.0, (sum, entry) => sum + entry.value);
		final double halfWeight = totalWeight / 2.0;
		
		double cumulativeWeight = 0.0;
		for (final entry in weightedValues) {
			cumulativeWeight += entry.value;
			if (cumulativeWeight >= halfWeight) {
				return entry.key;
			}
		}
		
		return weightedValues.last.key;
	}
	/// Add a new pitch estimate (Hz). If null, the window is unchanged.
	/// Returns the current smoothed pitch (median) or null if window is empty.
	/// Enhanced with outlier detection and weighted median filtering.
	double? add(double? pitchHz) {
		if (pitchHz != null && pitchHz.isFinite && pitchHz > 0) {
			// Check for outliers if we have enough statistics
			if (_isOutlier(pitchHz)) {
				_outlierCount++; // Count rejected outliers
				// Don't add outliers to the window
			} else {
				// Add to circular buffer
				_window[_writeIndex] = pitchHz;
				_writeIndex = (_writeIndex + 1) % windowSize;
				if (_currentSize < windowSize) {
					_currentSize++;
				}
				
				// Update statistics for future outlier detection
				_updateStatistics(pitchHz);
			}
		}
		
		if (_currentSize == 0) return null;
		
		// Collect valid values from circular buffer
		final List<double> validValues = [];
		for (int i = 0; i < _currentSize; i++) {
			final double? value = _window[i];
			if (value != null) {
				validValues.add(value);
			}
		}
		
		if (validValues.isEmpty) return null;
		
		// Use weighted median if enabled, otherwise regular median
		if (useWeightedMedian && validValues.length > 2) {
			return _calculateWeightedMedian(validValues);
		} else {
			// Regular median calculation
			validValues.sort();
			final int mid = validValues.length ~/ 2;
			if (validValues.length.isOdd) {
				return validValues[mid];
			} else {
				return 0.5 * (validValues[mid - 1] + validValues[mid]);
			}
		}
	}

	/// Clears internal state and resets all statistics.
	void reset() {
		_window.fillRange(0, windowSize, null);
		_writeIndex = 0;
		_currentSize = 0;
		_runningMean = 0.0;
		_runningVariance = 0.0;
		_statsCount = 0;
		_outlierCount = 0;
	}
	
	/// Gets current statistics for debugging/monitoring.
	Map<String, dynamic> getStatistics() {
		return {
			'currentSize': _currentSize,
			'runningMean': _runningMean,
			'runningStdDev': _statsCount > 1 ? math.sqrt(_runningVariance / (_statsCount - 1)) : 0.0,
			'statsCount': _statsCount,
			'outlierCount': _outlierCount,
			'outlierThreshold': outlierThreshold,
			'useWeightedMedian': useWeightedMedian,
		};
	}
}