import 'dart:math' as math;
import 'dart:typed_data';

/// Enhanced Voice Activity Detector with temporal smoothing, confidence scoring, and robustness improvements.
///
/// Features:
/// - Energy and zero-crossing rate analysis
/// - Temporal smoothing with hysteresis to prevent rapid switching
/// - Confidence scoring for decision quality assessment
/// - Adaptive thresholds based on environment
/// - Minimum duration requirements for voice/silence periods
class VoiceActivityDetector {
	final double sensitivity; // 0..1
	final int sampleRate;
	final int minVoiceDurationMs; // Minimum voice duration in milliseconds
	final int minSilenceDurationMs; // Minimum silence duration in milliseconds
	final double hysteresisMargin; // Hysteresis margin to prevent rapid switching

	// EMA of noise energy to adapt thresholds over time.
	double _noiseEnergy = 1e-6;
	bool _initialized = false;
	final double _emaAlpha = 0.05;
	
	// Temporal smoothing state
	bool _lastDecision = false;
	int _currentStateDurationMs = 0;
	int _frameCount = 0;
	
	// Confidence and quality metrics
	double _lastConfidence = 0.0;
	double _energyHistory = 0.0;
	double _zcrHistory = 0.0;
	final double _historyAlpha = 0.1;

	VoiceActivityDetector({
		required this.sampleRate,
		double sensitivity = 0.6,
		int minVoiceDurationMs = 100,
		int minSilenceDurationMs = 50,
		double hysteresisMargin = 0.2,
	}) : sensitivity = sensitivity.clamp(0.0, 1.0),
		 minVoiceDurationMs = minVoiceDurationMs.clamp(10, 1000),
		 minSilenceDurationMs = minSilenceDurationMs.clamp(10, 500),
		 hysteresisMargin = hysteresisMargin.clamp(0.0, 0.5);

	/// Compute zero crossing rate for the frame.
	double _zcr(Float64List x) {
		if (x.length < 2) return 0.0;
		int count = 0;
		for (int i = 1; i < x.length; i++) {
			if ((x[i - 1] >= 0 && x[i] < 0) || (x[i - 1] < 0 && x[i] >= 0)) {
				count++;
			}
		}
		return count / (x.length - 1);
	}
	
	/// Calculate confidence score optimized for noisy environments.
	double _calculateConfidence(double energy, double zcr, double energyThresh, double zcrThresh) {
		// Energy confidence: logarithmic scale for better noise handling
		final double energyRatio = energy / (energyThresh + 1e-10);
		final double energyConf = energyRatio > 1.0 
			? math.min(1.0, math.log(energyRatio + 1.0) / 2.0)
			: math.max(0.0, energyRatio - 0.3) / 0.7;
		
		// ZCR confidence: more tolerant of noise variations
		final double zcrDiff = (zcr - zcrThresh).abs() / (zcrThresh + 0.1);
		final double zcrConf = math.max(0.0, 1.0 - zcrDiff);
		
		// Weighted combination favoring energy over ZCR in noisy conditions
		final double rawConfidence = 0.7 * energyConf + 0.3 * zcrConf;
		
		// Apply smoothing to reduce jitter
		_lastConfidence = 0.6 * rawConfidence + 0.4 * _lastConfidence;
		
		return _lastConfidence.clamp(0.0, 1.0);
	}
	
	/// Apply temporal smoothing with hysteresis and minimum duration requirements.
	bool _applyTemporalSmoothing(bool rawDecision, int frameDurationMs) {
		_frameCount++;
		_currentStateDurationMs += frameDurationMs;
		
		// If decision hasn't changed, continue with current state
		if (rawDecision == _lastDecision) {
			return _lastDecision;
		}
		
		// Check minimum duration requirements
		final int minDuration = _lastDecision ? minVoiceDurationMs : minSilenceDurationMs;
		
		if (_currentStateDurationMs < minDuration) {
			// Haven't met minimum duration, keep current state
			return _lastDecision;
		}
		
		// Apply hysteresis with adaptive threshold based on noise conditions
		final double baseThreshold = 0.4; // Lower base threshold for noisy environments
		final double adaptiveMargin = hysteresisMargin * (1.0 - _lastConfidence * 0.3);
		final double confidenceThreshold = baseThreshold + adaptiveMargin;
		
		if (_lastConfidence < confidenceThreshold) {
			// Not confident enough to switch
			return _lastDecision;
		}
		
		// Switch state
		_lastDecision = rawDecision;
		_currentStateDurationMs = 0;
		return rawDecision;
	}

	/// Decide if the frame contains voice with enhanced robustness and confidence scoring.
	/// Returns true if voice is detected, false otherwise.
	bool isVoice(Float64List frame, {int frameDurationMs = 20}) {
		if (frame.isEmpty) return false;

		double energy = 0.0;
		for (int i = 0; i < frame.length; i++) {
			final double s = frame[i];
			energy += s * s;
		}
		energy /= math.max(frame.length, 1);

		if (!_initialized) {
			_noiseEnergy = math.max(energy, 1e-8);
			_initialized = true;
		}

		// Update noise estimate conservatively (only when energy is near noise).
		final double energyVsNoise = energy / (_noiseEnergy + 1e-9);
		if (energyVsNoise < 1.5) {
			_noiseEnergy = _emaAlpha * energy + (1.0 - _emaAlpha) * _noiseEnergy;
		}

		// Calculate features
		final double zcrVal = _zcr(frame);
		
		// Adaptive thresholds optimized for noisy environments
		final double energyThresh = (1.2 - 0.6 * sensitivity) * _noiseEnergy; // Lower threshold
		final double zcrVoiceMax = 0.35 + 0.2 * (1.0 - sensitivity); // More tolerant ZCR

		// Raw decision with improved logic for noisy conditions
		final bool energyVoice = energy > energyThresh;
		final bool zcrVoice = zcrVal < zcrVoiceMax;
		
		// Additional check: strong energy can override ZCR in very noisy conditions
		final bool strongEnergyOverride = energy > (3.0 * energyThresh);
		final bool rawDecision = energyVoice && (zcrVoice || strongEnergyOverride);
		
		// Calculate confidence for this decision
		_lastConfidence = _calculateConfidence(energy, zcrVal, energyThresh, zcrVoiceMax);
		
		// Update feature history for stability tracking
		_energyHistory = _historyAlpha * energy + (1.0 - _historyAlpha) * _energyHistory;
		_zcrHistory = _historyAlpha * zcrVal + (1.0 - _historyAlpha) * _zcrHistory;
		
		// Apply temporal smoothing
		return _applyTemporalSmoothing(rawDecision, frameDurationMs);
	}
	
	/// Get the confidence score of the last decision [0..1].
	double getLastConfidence() => _lastConfidence;
	
	/// Get current statistics for monitoring and debugging.
	Map<String, dynamic> getStatistics() {
		return {
			'noiseEnergy': _noiseEnergy,
			'lastConfidence': _lastConfidence,
			'currentStateDurationMs': _currentStateDurationMs,
			'frameCount': _frameCount,
			'energyHistory': _energyHistory,
			'zcrHistory': _zcrHistory,
			'lastDecision': _lastDecision,
			'sensitivity': sensitivity,
		};
	}
	
	/// Reset internal state for new audio session.
	void reset() {
		_noiseEnergy = 1e-6;
		_initialized = false;
		_lastDecision = false;
		_currentStateDurationMs = 0;
		_frameCount = 0;
		_lastConfidence = 0.0;
		_energyHistory = 0.0;
		_zcrHistory = 0.0;
	}
}