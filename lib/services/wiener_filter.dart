import 'dart:typed_data';
import 'dart:math' as math;

/// Lightweight Wiener-like noise reducer for real-time frames.
///
/// This implementation operates in the time domain to avoid FFT dependencies.
/// It maintains a running estimate of the noise floor using an exponential
/// moving average of frame energy during presumed non-voice periods.
///
/// API notes:
/// - Call [apply] on each PCM16 frame (little-endian) to obtain a cleaned
///   Float64List normalized to [-1, 1].
/// - Optionally call [updateNoiseFromNonVoice] with the same frame to refine
///   noise estimate when VAD reports non-voice.
/// - The [strength] parameter controls aggressiveness (0.0..1.0).
class WienerFilter {
	/// Aggressiveness of suppression [0..1]. Higher removes more but risks artifacts.
	final double strength;

	/// EMA factor for tracking noise energy.
	final double noiseEmaAlpha;

	/// Cached complement of EMA alpha for performance.
	final double _noiseEmaComplement;

	/// Floor to avoid complete attenuation.
	final double gainFloor;

	/// Cached complement of gain floor for performance.
	final double _gainFloorComplement;

	/// Strength-based exponent for gain calculation.
	final double _strengthExponent;

	double _noiseEnergy; // running estimate of noise energy (mean square)
	bool _initialized = false;

	// Reusable buffers to avoid memory allocation
	Float64List? _reusableBuffer;
	int _lastBufferSize = 0;

	WienerFilter({
		double strength = 0.5,
		double noiseEmaAlpha = 0.05,
		double gainFloor = 0.15,
	})  : strength = strength.clamp(0.0, 1.0),
			noiseEmaAlpha = noiseEmaAlpha.clamp(0.001, 0.5),
			_noiseEmaComplement = 1.0 - noiseEmaAlpha.clamp(0.001, 0.5),
			gainFloor = gainFloor.clamp(0.0, 0.9),
			_gainFloorComplement = 1.0 - gainFloor.clamp(0.0, 0.9),
			_strengthExponent = 1.0 + 2.0 * strength.clamp(0.0, 1.0),
			_noiseEnergy = 1e-6;

	/// Converts PCM16 LE bytes to normalized Float64 samples [-1, 1].
	/// Uses buffer reuse for better performance in real-time scenarios.
	Float64List _bytesToFloat64(Uint8List audioData) {
		final int length = audioData.length ~/ 2;
		
		// Reuse buffer if possible to avoid memory allocation
		if (_reusableBuffer == null || _lastBufferSize != length) {
			_reusableBuffer = Float64List(length);
			_lastBufferSize = length;
		}
		
		final Float64List buffer = _reusableBuffer!;
		final ByteData view = ByteData.sublistView(audioData);
		
		for (int i = 0; i < length; i++) {
			final int sample = view.getInt16(i * 2, Endian.little);
			buffer[i] = sample / 32768.0;
		}
		return buffer;
	}

	/// Updates the running noise energy estimate using an EMA.
	/// Improved numerical stability and performance.
	void _updateNoiseEnergy(Float64List frame) {
		if (frame.isEmpty) return;
		
		double energy = 0.0;
		for (int i = 0; i < frame.length; i++) {
			final double s = frame[i];
			energy += s * s;
		}
		energy /= frame.length;

		if (!_initialized) {
			_noiseEnergy = math.max(energy, 1e-8);
			_initialized = true;
			return;
		}

		// Use cached complement for better performance
		_noiseEnergy = noiseEmaAlpha * energy + _noiseEmaComplement * _noiseEnergy;
		// Ensure minimum noise floor for numerical stability
		_noiseEnergy = math.max(_noiseEnergy, 1e-10);
	}

	/// Applies a time-domain Wiener-like gain to the frame based on estimated SNR.
	/// Returns a new Float64List with the cleaned samples.
	/// Improved performance and numerical stability.
	Float64List apply(Uint8List pcm16LeFrame) {
		final Float64List x = _bytesToFloat64(pcm16LeFrame);
		if (x.isEmpty) return Float64List(0);

		// Estimate signal energy for this frame.
		double signalEnergy = 0.0;
		for (int i = 0; i < x.length; i++) {
			final double s = x[i];
			signalEnergy += s * s;
		}
		signalEnergy /= x.length;

		// Initialize noise on first frame if needed.
		if (!_initialized) {
			_noiseEnergy = math.max(signalEnergy, 1e-8);
			_initialized = true;
		}

		// Posterior SNR estimate with improved numerical stability.
		final double noiseFloor = math.max(_noiseEnergy, 1e-10);
		final double snr = math.max(0.0, signalEnergy - noiseFloor) / noiseFloor;
		
		// Wiener gain: G = SNR / (SNR + 1). Add strength to control aggressiveness.
		double gain = snr / (snr + 1.0);
		gain = gainFloor + _gainFloorComplement * math.pow(gain, _strengthExponent);

		// Apply gain with proper clamping
		final Float64List y = Float64List(x.length);
		for (int i = 0; i < x.length; i++) {
			y[i] = (x[i] * gain).clamp(-1.0, 1.0);
		}
		return y;
	}

	/// Call this when VAD says the frame is non-voice to refine noise estimate.
	void updateNoiseFromNonVoice(Float64List cleanedFrame) {
		_updateNoiseEnergy(cleanedFrame);
	}

	/// Get statistics about the filter performance
	Map<String, dynamic> getStatistics() {
		final double snrDb = _noiseEnergy > 0 ? 10 * math.log(_noiseEnergy) / math.ln10 : -60.0;
		return {
			'noiseEnergy': _noiseEnergy,
			'snrDb': snrDb,
			'initialized': _initialized,
			'strength': strength,
			'noiseReduction': _initialized ? (1.0 - gainFloor) * 100 : 0.0,
		};
	}

	/// Reset the filter state
	void reset() {
		_noiseEnergy = 1e-6;
		_initialized = false;
		_reusableBuffer = null;
		_lastBufferSize = 0;
	}
}